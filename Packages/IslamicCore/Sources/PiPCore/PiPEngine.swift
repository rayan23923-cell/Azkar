import Combine
import Foundation

/// The app's one PiP engine, shared by every section.
///
/// - **State**: the only `PiPState` in the app; screens read it, nobody else writes it.
/// - **Controllers**: each reader screen has its own platform `PiPController` (its inline layer
///   is the one the PiP window grows from) and registers it here with its section's
///   `PiPContentProvider`. At most one of them runs PiP at a time.
/// - **Switching sections**: starting PiP from another screen stops the running session first,
///   saves it, and starts the new one when the system reports the old window closed.
/// - **Controls** (`PiPNavigation`): play / pause drives the item's recording when one is
///   loaded; without one, play shows the next page of a long text and pause the previous one
///   (never the item). Skip back / forward changes the item; on a Hisn item with a count, skip
///   forward records one recitation until the count is complete. A recording that ends stays
///   on its item.
/// - **Progress**: PiP navigates and counts through the section's own reader, which saves its
///   position and its count at once. The session itself is saved in `PiPSessionStore`.
@MainActor
public final class PiPEngine: ObservableObject {
    @Published public private(set) var state: PiPState = .inactive
    @Published public private(set) var availability: PiPAvailability
    /// The section shown while a session runs.
    @Published public private(set) var activeContentType: PiPContentType?
    /// Called when the user taps "return to app" in the window, with the section shown.
    public var onRestoreUserInterface: ((PiPContentType) -> Void)?
    private let paginator: PiPPaginating
    private let sessionStore: PiPSessionStore
    private let now: () -> Date

    private typealias Pair = (provider: PiPContentProvider, controller: PiPController)
    private var active: Pair?
    private var pending: Pair?
    private var pages: PiPPageModel?
    /// Text mode: the play / pause button's next tap goes back a page (it shows pause). Set on
    /// reaching the last page, cleared on reaching the first, so every tap turns a page.
    private var pagingBack = false
    private var subscription: AnyCancellable?
    private var visibleControllers: Set<ObjectIdentifier> = []
    /// The provider of the last start request, so only its screen shows a failure.
    private var lastRequested: ObjectIdentifier?
    private var paginationCache: [String: PiPPagination] = [:]

    public init(paginator: PiPPaginating, sessionStore: PiPSessionStore, availability: PiPAvailability,
                now: @escaping () -> Date = Date.init) {
        self.paginator = paginator
        self.sessionStore = sessionStore
        self.availability = availability
        self.now = now
    }

    // MARK: Screens

    /// Connects a screen's controller and provider. Frames for the inline preview come from the
    /// provider at once; system events count only while this pair runs PiP.
    public func register(_ controller: PiPController, provider: PiPContentProvider) {
        controller.frameSource = { [weak self, weak provider] in
            guard let self, let provider else { return nil }
            return self.frame(for: provider)
        }
        controller.onEvent = { [weak self, weak controller] event in
            guard let self, let controller else { return }
            self.handle(event, from: controller)
        }
        controller.commands = self
    }

    /// The screen shows (or hides) the inline preview the window grows from.
    public func setInlineVisible(_ visible: Bool, for controller: PiPController) {
        let id = ObjectIdentifier(controller)
        if visible { visibleControllers.insert(id) } else { visibleControllers.remove(id) }
        updateHeartbeat(controller)
        if visible { controller.refresh() }
    }

    /// PiP can be offered on this screen: the build and the setting allow it and the device
    /// supports it.
    public func canOffer(on controller: PiPController) -> Bool {
        availability.isEnabled && controller.isSupported
    }

    /// This provider's content is the one in the PiP window.
    public func isRunning(_ provider: PiPContentProvider) -> Bool {
        state.isRunning && active?.provider === provider
    }

    /// The failure to show on this provider's screen, if its last request failed.
    public func failure(for provider: PiPContentProvider) -> PiPError? {
        guard lastRequested == ObjectIdentifier(provider) else { return nil }
        return state.error
    }

    public var session: PiPSession? { sessionStore.load() }

    // MARK: Start / stop

    /// Starts PiP for a section, on the user's request. A session of another screen is stopped
    /// first (stop, save, then the new session); asking again for the running one does nothing.
    public func start(_ provider: PiPContentProvider, on controller: PiPController) {
        lastRequested = ObjectIdentifier(provider)
        guard availability.isEnabled else { return reject(.disabled) }
        guard controller.isSupported else { return reject(.notSupported) }
        guard provider.current != nil else { return reject(.noContent) }
        if let active, state.isRunning {
            if active.provider === provider && active.controller === controller { return }
            pending = (provider, controller)
            if state != .stopping { active.controller.stop() }
            return
        }
        begin(provider, controller)
    }

    /// Closes the window (the progress stays where it is).
    public func stop() {
        pending = nil
        guard let active, state.isRunning, state != .stopping else { return }
        active.controller.stop()
    }

    /// Closes the window if it shows this provider (its screen is going away).
    public func stop(ifShowing provider: PiPContentProvider) {
        guard active?.provider === provider else { return }
        stop()
    }

    /// The «العرض العائم» setting.
    public func setUserEnabled(_ enabled: Bool) {
        availability.userEnabled = enabled
        if !availability.isEnabled { stop() }
    }

    private func reject(_ error: PiPError) {
        state = state.applying(.rejected(error))
    }

    private func begin(_ provider: PiPContentProvider, _ controller: PiPController) {
        guard let content = provider.current else { return reject(.noContent) }
        active = (provider, controller)
        activeContentType = content.contentType
        pages = pageModel(for: content)
        pagingBack = false
        state = state.applying(.startRequested)
        subscription = provider.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.contentChanged() }
            }
        saveSession()
        updateHeartbeat(controller)
        controller.refresh()
        controller.start()
    }

    /// The session ended (closed by the user, by the system, or replaced).
    private func end() {
        guard let finished = active else { return }
        finished.provider.persist()
        saveSession(.closed)
        subscription = nil
        active = nil
        activeContentType = nil
        pages = nil
        pagingBack = false
        updateHeartbeat(finished.controller)
    }

    // MARK: System events

    private func handle(_ event: PiPControllerEvent, from controller: PiPController) {
        switch event {
        case .possibleChanged:
            // Screens read `isPossible` from their controller; let them refresh.
            objectWillChange.send()
            return
        case .restoreUserInterface:
            if active?.controller === controller, let type = activeContentType { onRestoreUserInterface?(type) }
            return
        default:
            break
        }
        // Late events from a controller whose session already ended are ignored.
        guard let active, active.controller === controller else { return }
        switch event {
        case .willStart:
            state = state.applying(.willStart)
        case .didStart:
            state = state.applying(.didStart(playing: isPlaying))
            saveSession()
        case .failedToStart:
            pending = nil
            end()
            state = state.applying(.failedToStart)
        case .willStop:
            state = state.applying(.willStop)
        case .didStop:
            end()
            state = state.applying(.didStop)
            if let next = pending {
                pending = nil
                begin(next.provider, next.controller)
            }
        case .possibleChanged, .restoreUserInterface:
            break
        }
        updateHeartbeat(controller)
    }

    /// The item, its counter or the recording changed (in PiP or on the screen).
    private func contentChanged() {
        guard let active else { return }
        guard let content = active.provider.current else {
            // Nothing left to show (the chapter or collection was completed): close the window.
            if state.isRunning && state != .stopping { active.controller.stop() }
            return
        }
        if pages?.contentID != content.contentID {
            pages = pageModel(for: content)
            pagingBack = false
        }
        state = state.applying(.playingChanged(isPlaying))
        saveSession()
        active.controller.refresh()
    }

    private func updateHeartbeat(_ controller: PiPController) {
        let runsPiP = active?.controller === controller && state.isRunning
        controller.setHeartbeat(visibleControllers.contains(ObjectIdentifier(controller)) || runsPiP)
    }

    // MARK: Frames

    /// The frame for a provider: the running session's page and playback when it is the active
    /// one, otherwise its first page, not playing (the inline preview).
    public func frame(for provider: PiPContentProvider) -> PiPFrame? {
        guard let content = provider.current else { return nil }
        let isActive = active?.provider === provider
        var model = pageModel(for: content)
        if isActive, let pages, pages.contentID == content.contentID { model = pages }
        let playback = provider.playback.flatMap { $0.isAvailable ? $0 : nil }
        if let playback {
            let playing = isActive ? isPlaying : playback.isPlaying
            return PiPFrame(content: content, pageText: model.pageText, page: model.currentPage,
                            pageCount: model.totalPages, fontSize: model.pagination.fontSize, mode: .audio,
                            isPlaying: playing, time: playback.currentTime, duration: playback.duration ?? 0,
                            rate: playing ? 1 : 0)
        }
        // Text: the play / pause button shows pause while its next tap goes back a page.
        let showsPause = isActive && pagingBack && model.hasPages
        // The system progress bar shows the place in the container.
        let time = Double(content.index) + Double(model.currentPage + 1) / Double(model.totalPages)
        return PiPFrame(content: content, pageText: model.pageText, page: model.currentPage,
                        pageCount: model.totalPages, fontSize: model.pagination.fontSize, mode: .text,
                        isPlaying: showsPause, time: time, duration: Double(content.total), rate: 0)
    }

    /// The running session's page (0-based) and page count.
    public var currentPage: (page: Int, total: Int)? {
        pages.map { ($0.currentPage, $0.totalPages) }
    }

    /// A recording plays. Text never plays: its pages turn only on a tap.
    private var isPlaying: Bool {
        guard let playback = active?.provider.playback, playback.isAvailable else { return false }
        return playback.isPlaying
    }

    private func pageModel(for content: PiPContent) -> PiPPageModel {
        let key = "\(content.textStyle.rawValue)|\(content.text)"
        let pagination: PiPPagination
        if let cached = paginationCache[key] {
            pagination = cached
        } else {
            pagination = paginator.paginate(content.text, style: content.textStyle)
            if paginationCache.count >= 32 { paginationCache.removeAll() }
            paginationCache[key] = pagination
        }
        return PiPPageModel(contentID: content.contentID, pagination: pagination)
    }

    private func saveSession(_ status: PiPSession.Status? = nil) {
        let resolved = status ?? (state == .active ? .active : .paused)
        if let content = active?.provider.current {
            sessionStore.save(PiPSession(domain: content.contentType, contentID: content.contentID,
                                         containerID: content.containerID, index: content.index,
                                         page: pages?.contentID == content.contentID ? pages?.currentPage ?? 0 : 0,
                                         status: resolved, savedAt: now()))
        } else if let last = sessionStore.load() {
            sessionStore.save(PiPSession(domain: last.domain, contentID: last.contentID,
                                         containerID: last.containerID, index: last.index, page: last.page,
                                         status: resolved, savedAt: now()))
        }
    }
}

// MARK: - System buttons

extension PiPEngine: PiPCommandHandling {
    /// Play / pause. With a recording: the recording. Without one: play shows the next page of a
    /// long text, pause the previous one, stopping at the first and last page; a one-page text
    /// has nothing to turn. The page is drawn at once.
    public func setPlaying(_ playing: Bool) {
        guard let active, let content = active.provider.current else { return }
        if let playback = active.provider.playback, playback.isAvailable {
            if playing { playback.play() } else { playback.pause() }
            state = state.applying(.playingChanged(isPlaying))
        } else {
            if pages?.contentID != content.contentID {
                pages = pageModel(for: content)
                pagingBack = false
            }
            guard var model = pages else { return }
            switch PiPNavigation.page(playing: playing, pages: model) {
            case .nextPage: model.nextPage()
            case .previousPage: model.previousPage()
            default: break
            }
            pages = model
            if model.isLastPage && model.hasPages { pagingBack = true }
            if model.isFirstPage { pagingBack = false }
        }
        saveSession()
        // Also when nothing moved: the system shows its own guess of the button until asked.
        active.controller.refresh()
    }

    /// Skip back / forward: the previous / next item, or one recitation of a Hisn item.
    public func skip(by seconds: TimeInterval) {
        guard let direction = PiPNavigation.Direction(skip: seconds), let active,
              let content = active.provider.current else { return }
        switch PiPNavigation.resolve(direction, content: content) {
        case .countRepetition:
            active.provider.recordRepetition()
            contentChanged()
        case .nextItem:
            active.provider.goToNext()
            contentChanged()
        case .previousItem:
            active.provider.goToPrevious()
            contentChanged()
        case .nextPage, .previousPage, .none:
            break
        }
        saveSession()
        active.controller.refresh()
    }
}
