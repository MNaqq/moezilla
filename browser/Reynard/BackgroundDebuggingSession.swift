//
//  BackgroundDebuggingSession.swift
//  Moezilla
//
//  Foreground-initiated, explicitly stoppable remote-debugging session.
//  iOS may expire a continued-processing task or suspend Gecko at any time.
//

import UIKit
import BackgroundTasks

final class BackgroundDebuggingSession {
    static let shared = BackgroundDebuggingSession()

    private static let taskIdentifier = "com.bonewizardry.Moezilla.backgroundDebugging"
    private var continuedTask: BGTask?
    private var legacyBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    private(set) var isRunning = false

    enum SessionError: LocalizedError {
        case remoteDebuggingDisabled
        case registrationFailed
        case unableToStart

        var errorDescription: String? {
            switch self {
            case .remoteDebuggingDisabled:
                return "Enable USB remote debugging first."
            case .registrationFailed:
                return "iOS could not register Moezilla's background session."
            case .unableToStart:
                return "iOS did not grant background execution for this session."
            }
        }
    }

    private var registrationSucceeded = false

    private init() {}

    func register() {
        if #available(iOS 26.0, *) {
            registrationSucceeded = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.taskIdentifier,
                using: nil
            ) { [weak self] task in
                self?.handle(task)
            }
        } else {
            registrationSucceeded = true
        }
    }

    /// Must be invoked by the user while Moezilla is in the foreground.
    func start() throws {
        guard Prefs.DeveloperSettings.remoteDebuggingEnabled else {
            throw SessionError.remoteDebuggingDisabled
        }
        guard !isRunning else { return }
        guard registrationSucceeded else {
            throw SessionError.registrationFailed
        }

        RemoteDebuggingSettingController.applyRemoteDebugging()
        // Set before submitting: iOS may invoke the launch handler promptly.
        isRunning = true

        if #available(iOS 26.0, *) {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.taskIdentifier,
                title: "Moezilla remote debugging",
                subtitle: "Active USB automation session"
            )
            request.strategy = .fail
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                isRunning = false
                throw error
            }
        } else {
            legacyBackgroundTask = UIApplication.shared.beginBackgroundTask(
                withName: "Moezilla Remote Debugging"
            ) { [weak self] in
                DispatchQueue.main.async {
                    self?.stop(success: false)
                }
            }
            guard legacyBackgroundTask != .invalid else {
                isRunning = false
                throw SessionError.unableToStart
            }
        }
    }

    private func handle(_ task: BGTask) {
        guard isRunning else {
            task.setTaskCompleted(success: false)
            return
        }
        continuedTask = task
        if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
            task.progress.totalUnitCount = 1
            task.progress.completedUnitCount = 0
        }
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.stop(success: false)
            }
        }
    }

    func stop(success: Bool = true) {
        isRunning = false

        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        }
        if let task = continuedTask {
            if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
                task.progress.completedUnitCount = task.progress.totalUnitCount
            }
            task.setTaskCompleted(success: success)
            continuedTask = nil
        }
        if legacyBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(legacyBackgroundTask)
            legacyBackgroundTask = .invalid
        }

        // If iOS ends the continued task while Moezilla is backgrounded,
        // let the original Gecko lifecycle stop foreground-only work.
        if UIApplication.shared.applicationState == .background {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene,
                      let browser = windowScene.windows.first?.rootViewController
                        as? BrowserViewController else {
                    continue
                }
                browser.sessionManager.setApplicationForeground(false)
            }
        }
    }

    func restoreRemoteDebuggingOnForeground() {
        // This reapplies debugger preferences when iOS resumes the process,
        // without silently launching a new background job.
        if Prefs.DeveloperSettings.remoteDebuggingEnabled {
            RemoteDebuggingSettingController.applyRemoteDebugging()
        }
    }
}
