//
//  TipTransaction.swift
//  StitchSocial
//
//  Created by James Garmon on 3/11/26.
//


//
//  TipTypes.swift
//  StitchSocial
//
//  Data models for the tip mechanic.
//  Mirrors EngagementTypes pattern — structs only, no logic.
//

import Foundation

// MARK: - TipTransaction

/// A single flushed tip batch written to Firestore.
struct TipTransaction: Codable {
    let id: String
    let videoID: String
    let tipperID: String
    let creatorID: String
    let amount: Int          // total coins in this batch
    let cloutBonus: Int      // clout awarded to creator this flush
    let createdAt: Date

    init(videoID: String, tipperID: String, creatorID: String, amount: Int) {
        self.id         = "\(videoID)_\(tipperID)_tip_\(Int(Date().timeIntervalSince1970))"
        self.videoID    = videoID
        self.tipperID   = tipperID
        self.creatorID  = creatorID
        self.amount     = amount
        self.cloutBonus = TipConfig.cloutBonusPerFlush
        self.createdAt  = Date()
    }
}

// MARK: - TipResult

/// Server response after Cloud Function processes a tip flush.
enum TipResult {
    case success(amountSent: Int, newTipperBalance: Int)
    case insufficientFunds(available: Int, requested: Int)
    case selfTip
    case failure(Error)
}

// MARK: - TipState

/// Local per-video session state — never written to Firestore directly.
/// Cleared when video changes.
struct TipState {
    var sessionTotal: Int       = 0  // coins tipped this session
    var pendingAmount: Int      = 0  // buffered, not yet flushed
    var lastFlushAt: Date?           = nil
    var isFlushing: Bool        = false

    var hasPending: Bool { pendingAmount > 0 }
}

// MARK: - ButtonMode

/// Which button is showing in the swappable slot.
enum EngagementButtonMode {
    case hype
    case tip
}