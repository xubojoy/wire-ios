//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//


import Foundation
import MessageUI


extension SettingsCellDescriptorFactory {

    func developerGroup() -> SettingsCellDescriptorType {
        let title = "self.settings.developer_options.title".localized
        
        let devController = SettingsExternalScreenCellDescriptor(title: "Logging") { () -> (UIViewController?) in
            return DevOptionsController()
        }
        
        let diableAVSSetting = SettingsPropertyToggleCellDescriptor(settingsProperty: self.settingsPropertyFactory.property(.DisableAVS))
        let diableUISetting = SettingsPropertyToggleCellDescriptor(settingsProperty: self.settingsPropertyFactory.property(.DisableUI))
        let diableHockeySetting = SettingsPropertyToggleCellDescriptor(settingsProperty: self.settingsPropertyFactory.property(.DisableHockey))
        let diableAnalyticsSetting = SettingsPropertyToggleCellDescriptor(settingsProperty: self.settingsPropertyFactory.property(.DisableAnalytics))
        
        let debugOptions = SettingsExternalScreenCellDescriptor.debugOptions
        
        return SettingsGroupCellDescriptor(items: [
            SettingsSectionDescriptor(cellDescriptors: [
                devController,
                diableAVSSetting,
                diableUISetting,
                diableHockeySetting,
                diableAnalyticsSetting,
                debugOptions
                ])
            ], title: title, icon: .effectRobot)
    }
    
}

extension SettingsExternalScreenCellDescriptor {
    static var debugOptions: SettingsExternalScreenCellDescriptor = {
        return SettingsExternalScreenCellDescriptor(title: "Debug Actions", isDestructive: false, presentationStyle: .modal, presentationAction: { () -> UIViewController in
            let controller = UIAlertController(title: "Debug Actions", message: nil, preferredStyle: .alert)
            
            
            let dismissingAction: (String, (() -> Void)?) -> UIAlertAction = { title, block in
                return UIAlertAction(title: title, style: .default) { _ in
                    block?()
                    controller.dismiss(animated: true, completion: nil)
                }
            }
            
            let simulateInactive = dismissingAction("404 on /notifications (add sys-msg top)") {
                ZMUser.selfUser().managedObjectContext?.setPersistentStoreMetadata("00000000-0000-0000-0000-000000000000", forKey: "LastUpdateEventID")
            }
            
            let uploadAddressBook = dismissingAction("Force upload address book") {
                AddressBookHelper.sharedHelper.startRemoteSearch(false)
            }
            
            let send500Times = dismissingAction("Send next text message 500 times") {
                Settings.shared().shouldSend500Messages = true
            }
            
            let decreaseMaxRecording = dismissingAction("Decrease max audio recording to 5 sec") {
                Settings.shared().maxRecordingDurationDebug = 5
            }
            
            let logSnapshot = UIAlertAction(title: "Make a log snapshot", style: .default) { _ in
                
                let caches = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let name = "\(Bundle.main.bundleIdentifier!)\(NSDate()).log"
                let path = caches.appendingPathComponent(name).path
                ZMLogSnapshot(path)
                controller.dismiss(animated: true, completion: nil)
                
                guard MFMailComposeViewController.canSendMail() else { return }
                let mailComposer = MFMailComposeViewController()
                mailComposer.setToRecipients(["ios@wire.com"])
                mailComposer.setSubject("Logs from Wire")
                mailComposer.addAttachmentData(try! Data(contentsOf: URL(string: path)!), mimeType: "text/plain", fileName: name)
                
                //                mailComposer.mailComposeDelegate = self
                UIApplication.shared.keyWindow?.rootViewController?.present(mailComposer, animated: true, completion: .none)
            }
            
            let cancel = dismissingAction("Cancel", nil)
            
            controller.addActions(simulateInactive, uploadAddressBook, send500Times, decreaseMaxRecording, logSnapshot, cancel)
            return controller
        })
    }()
}

extension UIAlertController {
    func addActions(_ actions: UIAlertAction...) {
        actions.forEach(addAction)
    }
}

