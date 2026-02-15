//
//  StreamChatService.swift
//  StitchSocial
//
//  Layer 3: Services - Live Stream Chat
//  Real-time Firestore listener on communities/{creatorID}/streams/{streamID}/chat
//  Shared singleton between creator view and viewer view.
//
//  CACHING: Real-time listener — no polling. One listener per stream session.
//           Messages kept in memory (last 100). Listener removed on cleanup.
//  BATCHING: sendMessage is a single write per message. No batching needed.
//

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Chat Message Model

struct StreamChatMessage: Identifiable, Equatable {
    let id: String
    let streamID: String
    let authorID: String
    let authorUsername: String
    let authorDisplayName: String
    let authorLevel: Int
    let isCreator: Bool
    let body: String
    let messageType: String       // "text", "system", "freeHype", "gift"
    let createdAt: Date
    
    init(
        streamID: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorLevel: Int,
        isCreator: Bool,
        body: String,
        messageType: String = "text"
    ) {
        self.id = UUID().uuidString
        self.streamID = streamID
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorLevel = authorLevel
        self.isCreator = isCreator
        self.body = body
        self.messageType = messageType
        self.createdAt = Date()
    }
    
    /// Build from Firestore document
    init?(id: String, data: [String: Any]) {
        guard let streamID = data["streamID"] as? String,
              let authorID = data["authorID"] as? String,
              let authorUsername = data["authorUsername"] as? String,
              let body = data["body"] as? String else { return nil }
        
        self.id = id
        self.streamID = streamID
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = data["authorDisplayName"] as? String ?? authorUsername
        self.authorLevel = data["authorLevel"] as? Int ?? 0
        self.isCreator = data["isCreator"] as? Bool ?? false
        self.body = body
        self.messageType = data["messageType"] as? String ?? "text"
        
        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = Date()
        }
    }
    
    /// Convert to Firestore dictionary (uses Timestamp, not Date)
    var firestoreData: [String: Any] {
        [
            "streamID": streamID,
            "authorID": authorID,
            "authorUsername": authorUsername,
            "authorDisplayName": authorDisplayName,
            "authorLevel": authorLevel,
            "isCreator": isCreator,
            "body": body,
            "messageType": messageType,
            "createdAt": Timestamp(date: createdAt)
        ]
    }
    
    var isSystem: Bool { messageType == "system" }
    var isGift: Bool { messageType == "gift" }
    var isFreeHype: Bool { messageType == "freeHype" }
}

// MARK: - Service

@MainActor
class StreamChatService: ObservableObject {
    static let shared = StreamChatService()
    
    @Published var messages: [StreamChatMessage] = []
    
    private let db = FirebaseConfig.firestore
    private var chatListener: ListenerRegistration?
    private let maxLocalMessages = 100
    
    // MARK: - Listen
    
    /// Start real-time listener on chat subcollection.
    /// Cost: 1 listener. Reads only new docs after attach.
    nonisolated func startListening(communityID: String, streamID: String) {
        let db = FirebaseConfig.firestore
        
        Task { @MainActor in
            self.stopListening()
            self.messages = []
            
            self.chatListener = db.collection("communities")
                .document(communityID)
                .collection("streams")
                .document(streamID)
                .collection("chat")
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { [weak self] snapshot, error in
                    if let error {
                        print("⚠️ CHAT: Listener error — \(error.localizedDescription)")
                        return
                    }
                    guard let snapshot else { return }
                    
                    Task { @MainActor in
                        guard let self else { return }
                        for change in snapshot.documentChanges {
                            if change.type == .added {
                                if let msg = StreamChatMessage(
                                    id: change.document.documentID,
                                    data: change.document.data()
                                ) {
                                    self.messages.append(msg)
                                    if self.messages.count > self.maxLocalMessages {
                                        self.messages.removeFirst(self.messages.count - self.maxLocalMessages)
                                    }
                                }
                            }
                        }
                    }
                }
            
            print("💬 CHAT: Listening on communities/\(communityID)/streams/\(streamID)/chat")
        }
    }
    
    func stopListening() {
        chatListener?.remove()
        chatListener = nil
    }
    
    // MARK: - Send Message
    
    /// Cost: 1 write per message. Uses raw dictionary to avoid Codable/Date issues.
    nonisolated func sendMessage(
        communityID: String,
        streamID: String,
        authorID: String,
        authorUsername: String,
        authorDisplayName: String,
        authorLevel: Int,
        isCreator: Bool,
        body: String,
        messageType: String = "text"
    ) {
        let msg = StreamChatMessage(
            streamID: streamID,
            authorID: authorID,
            authorUsername: authorUsername,
            authorDisplayName: authorDisplayName,
            authorLevel: authorLevel,
            isCreator: isCreator,
            body: body,
            messageType: messageType
        )
        
        let db = FirebaseConfig.firestore
        db.collection("communities")
            .document(communityID)
            .collection("streams")
            .document(streamID)
            .collection("chat")
            .document(msg.id)
            .setData(msg.firestoreData) { error in
                if let error {
                    print("⚠️ CHAT: Send failed — \(error.localizedDescription)")
                }
            }
    }
    
    /// Send a system message (join, leave). Fire-and-forget.
    nonisolated func sendSystemMessage(communityID: String, streamID: String, body: String) {
        sendMessage(
            communityID: communityID,
            streamID: streamID,
            authorID: "system",
            authorUsername: "System",
            authorDisplayName: "System",
            authorLevel: 0,
            isCreator: false,
            body: body,
            messageType: "system"
        )
    }
    
    /// Send free hype chat message. Fire-and-forget.
    nonisolated func sendFreeHypeMessage(communityID: String, streamID: String, username: String) {
        sendMessage(
            communityID: communityID,
            streamID: streamID,
            authorID: "system",
            authorUsername: username,
            authorDisplayName: username,
            authorLevel: 0,
            isCreator: false,
            body: "🔥 \(username) hyped!",
            messageType: "freeHype"
        )
    }
    
    /// Send gift announcement. Fire-and-forget.
    nonisolated func sendGiftMessage(communityID: String, streamID: String, username: String, giftName: String, emoji: String) {
        sendMessage(
            communityID: communityID,
            streamID: streamID,
            authorID: "system",
            authorUsername: username,
            authorDisplayName: username,
            authorLevel: 0,
            isCreator: false,
            body: "\(emoji) \(username) sent \(giftName)!",
            messageType: "gift"
        )
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        stopListening()
        messages = []
    }
}
