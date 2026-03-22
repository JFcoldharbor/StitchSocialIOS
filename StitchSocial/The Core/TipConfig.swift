//
//  TipConfig.swift
//  StitchSocial
//
//  Created by James Garmon on 3/11/26.
//


//
//  TipConfig.swift
//  StitchSocial
//
//  Tip mechanic constants. All tip logic gates here — change once, applies everywhere.
//  No Firestore reads. No caching needed.
//

import Foundation

enum TipConfig {

    // MARK: - Tip Amounts
    static let singleTapAmount: Int   = 1   // coins per tap
    static let longPressAmount: Int   = 5   // coins per long press
    static let longPressDuration: Double = 0.4  // seconds to trigger long press

    // MARK: - Batching / Flush
    /// Accumulate taps locally, flush to Firestore after this idle window.
    /// Prevents per-tap writes. Add pattern to caching optimization file.
    static let flushDebounceInterval: TimeInterval = 1.5

    // MARK: - Creator Clout Bonus
    /// Awarded once per flush event (not per tap) to keep clout meaningful.
    static let cloutBonusPerFlush: Int = 2

    // MARK: - Balance Protection
    /// Minimum balance required before tip button enables.
    static let minimumBalanceRequired: Int = 1

    // MARK: - UI
    static let selfTipErrorMessage  = "You can't tip your own video"
    static let insufficientFundsMessage = "Not enough HypeCoins"
    static let sessionTipLabelFormat = "+%d 🪙"  // e.g. "+12 🪙"
}