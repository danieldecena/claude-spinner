//
//  LoginItem.swift
//  claude spinner
//
//  Thin wrapper over SMAppService for the "Launch at Login" toggle.
//

import Foundation
import Observation
import ServiceManagement

@Observable
final class LoginItem {
    var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Registration can fail when the app runs from DerivedData rather
            // than /Applications; surface nothing here, just resync the toggle.
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
