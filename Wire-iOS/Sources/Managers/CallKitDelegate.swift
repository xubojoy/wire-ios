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
import UIKit
import CallKit
import zmessaging
import CocoaLumberjackSwift

final class ZMCall: NSObject {
    let conversation: ZMConversation
    let isOutgoing: Bool
    
    init(conversation: ZMConversation, isOutgoing: Bool) {
        self.conversation = conversation
        self.isOutgoing = isOutgoing
        super.init()
    }
}

@available(iOS 10.0, *)
final class CallKitDelegate: NSObject, CXProviderDelegate {

    private let userSession: ZMUserSession
    private let analyics: Analytics
    private let mediaManager: AVSMediaManager
    private let provider: CXProvider

    init(userSession: ZMUserSession, analytics: Analytics, mediaManager: AVSMediaManager) {
        provider = CXProvider(configuration: type(of: self).providerConfiguration)
        self.userSession = userSession
        self.analytics = analytics
        self.mediaManager = mediaManager
        
        super.init()

        provider.setDelegate(self, queue: nil)
    }

    static var providerConfiguration: CXProviderConfiguration {
        let localizedName = Bundle.main.infoDictionary?["CFBundleName"] as? String
        let providerConfiguration = CXProviderConfiguration(localizedName: localizedName ?? "Wire")

        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.phoneNumber, .emailAddress]
        providerConfiguration.iconTemplateImageData = UIImagePNGRepresentation(UIImage.init(forLogoWith: .white, iconSize: .large))
        
        let propertyFactory = SettingsPropertyFactory(userDefaults: UserDefaults.standard,
                                                      analytics: self.analytics,
                                                      mediaManager: self.mediaManager,
                                                      userSession: self.userSession,
                                                      selfUser: ZMUser.selfUser())
        if let ringtoneSound = propertyFactory.property(.CallSoundName).propertyValue.value() as? String {
            providerConfiguration.ringtoneSound = ringtoneSound
        }
        else {
            providerConfiguration.ringtoneSound = ZMSound.ringtones.first?.filename() ?? ""
        }
        
        return providerConfiguration
    }

    // MARK: - Incoming Calls

    /// Use CXProvider to report the incoming call to the system
    func incomingCall(in conversation: ZMConversation, video: Bool = false, completion: ((NSError?) -> Void)? = nil) {
        guard let callConversationUUID = conversation.remoteIdentifier else {
            return
        }
        // Construct a CXCallUpdate describing the incoming call, including the caller.
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: callConversationUUID.uuidString)
        update.hasVideo = video

        // Report the incoming call to the system
        provider.reportNewIncomingCall(with: callConversationUUID, update: update) { error in
            
            if error == nil {
                // all good, continue ringing
            }
            else {
                conversation.voiceChannel.leave()
                DDLogError("Cannot report incoming call: \(error)")
            }
            
            completion?(error as? NSError)
        }
    }

    // MARK: - CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        ZMConversation.leaveActiveCalls(completionHandler: .none)
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        // Create & configure an instance of SpeakerboxCall, the app's model class representing the new outgoing call.
        let call = SpeakerboxCall(uuid: action.callUUID, isOutgoing: true)
        call.handle = action.handle.value

        /*
            Configure the audio session, but do not start call audio here, since it must be done once
            the audio session has been activated by the system after having its priority elevated.
         */
        configureAudioSession()

        /*
            Set callback blocks for significant events in the call's lifecycle, so that the CXProvider may be updated
            to reflect the updated state.
         */
        call.hasStartedConnectingDidChange = { [weak self] in
            self?.provider.reportOutgoingCall(with: call.uuid, startedConnectingAt: call.connectingDate)
        }
        call.hasConnectedDidChange = { [weak self] in
            self?.provider.reportOutgoingCall(with: call.uuid, connectedAt: call.connectDate)
        }

        // Trigger the call to be started via the underlying network service.
        call.startSpeakerboxCall { success in
            if success {
                // Signal to the system that the action has been successfully performed.
                action.fulfill()

                // Add the new outgoing call to the app's list of calls.
                self.callManager.addCall(call)
            } else {
                // Signal to the system that the action was unable to be performed.
                action.fail()
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // Retrieve the SpeakerboxCall instance corresponding to the action's call UUID
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }

        /*
            Configure the audio session, but do not start call audio here, since it must be done once
            the audio session has been activated by the system after having its priority elevated.
         */
        configureAudioSession()

        // Trigger the call to be answered via the underlying network service.
        call.answerSpeakerboxCall()

        // Signal to the system that the action has been successfully performed.
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        // Retrieve the SpeakerboxCall instance corresponding to the action's call UUID
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }

        // Stop call audio whenever ending the call.
        stopAudio()

        // Trigger the call to be ended via the underlying network service.
        call.endSpeakerboxCall()

        // Signal to the system that the action has been successfully performed.
        action.fulfill()

        // Remove the ended call from the app's list of calls.
        callManager.removeCall(call)
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        // Retrieve the SpeakerboxCall instance corresponding to the action's call UUID
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }

        // Update the SpeakerboxCall's underlying hold state.
        call.isOnHold = action.isOnHold

        // Stop or start audio in response to holding or unholding the call.
        if call.isOnHold {
            stopAudio()
        } else {
            startAudio()
        }

        // Signal to the system that the action has been successfully performed.
        action.fulfill()
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        print("Timed out \(#function)")

        // React to the action timeout if necessary, such as showing an error UI.
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("Received \(#function)")

        // Start call audio media, now that the audio session has been activated after having its priority boosted.
        startAudio()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("Received \(#function)")

        /*
             Restart any non-call related audio now that the app's audio session has been
             de-activated after having its priority restored to normal.
         */
    }

}
