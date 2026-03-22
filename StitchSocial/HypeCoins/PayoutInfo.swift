//
//  PayoutInfo.swift
//  StitchSocial
//
//  Created by James Garmon on 3/16/26.
//


//
//  CashOutView.swift
//  StitchSocial
//
//  Cash out wizard — 3 steps: Amount, Payout Method, Confirm.
//  Saves payout info to Firestore so users only enter it once.
//  Uses effectiveCreatorShare for ambassador promo overrides.
//
//  Firestore: users/{userID}/private/payoutInfo
//  CACHING: Payout info loaded once on appear, saved on change.
//  No extra reads — single doc fetch, single doc write.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Saved Payout Info (Firestore)

struct PayoutInfo: Codable {
    var method: String          // "bank_transfer", "paypal", "stripe"
    var paypalEmail: String?
    var bankAccountName: String?
    var bankRoutingNumber: String?
    var bankAccountNumber: String?
    var bankAccountLast4: String?   // Display only — never show full number after save
    var stripeConnectID: String?
    var updatedAt: Date
    
    var methodEnum: PayoutMethod {
        PayoutMethod(rawValue: method) ?? .paypal
    }
    
    var displaySummary: String {
        switch methodEnum {
        case .paypal:
            return "PayPal: \(paypalEmail ?? "Not set")"
        case .bankTransfer:
            return "Bank: ****\(bankAccountLast4 ?? "????")"
        case .stripe:
            return "Stripe Connect"
        }
    }
    
    var isComplete: Bool {
        switch methodEnum {
        case .paypal: return paypalEmail != nil && !(paypalEmail?.isEmpty ?? true)
        case .bankTransfer: return bankAccountNumber != nil && bankRoutingNumber != nil && bankAccountName != nil
        case .stripe: return stripeConnectID != nil
        }
    }
}

// MARK: - Cash Out Sheet

struct CashOutSheet: View {
    let userID: String
    let userTier: UserTier
    let availableCoins: Int
    
    @Environment(\.dismiss) private var dismiss
    
    // Step navigation
    @State private var currentStep = 0
    
    // Step 1: Amount
    @State private var cashOutAmount: String = ""
    
    // Step 2: Payout method
    @State private var selectedMethod: PayoutMethod = .paypal
    @State private var paypalEmail: String = ""
    @State private var bankAccountName: String = ""
    @State private var bankRoutingNumber: String = ""
    @State private var bankAccountNumber: String = ""
    
    // Saved info
    @State private var savedPayoutInfo: PayoutInfo?
    @State private var isLoadingPayout = true
    @State private var useSavedMethod = true
    
    // Custom share (auto-fetched from user doc)
    @State private var effectiveShare: Double = 0
    @State private var shareLabel: String = ""
    
    // Processing
    @State private var isProcessing = false
    @State private var showingSuccess = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    private let db = FirebaseConfig.firestore
    
    private var coinAmount: Int { Int(cashOutAmount) ?? 0 }
    
    private var creatorAmount: Double {
        HypeCoinValue.toDollars(coinAmount) * effectiveShare
    }
    
    private var platformAmount: Double {
        HypeCoinValue.toDollars(coinAmount) * (1.0 - effectiveShare)
    }
    
    private var isValidAmount: Bool {
        coinAmount >= CashOutLimits.minimumCoins && coinAmount <= availableCoins
    }
    
    private var activeMethod: PayoutMethod {
        if useSavedMethod, let saved = savedPayoutInfo {
            return saved.methodEnum
        }
        return selectedMethod
    }
    
    private var isPayoutComplete: Bool {
        if useSavedMethod, let saved = savedPayoutInfo, saved.isComplete { return true }
        switch selectedMethod {
        case .paypal: return !paypalEmail.isEmpty && paypalEmail.contains("@")
        case .bankTransfer: return !bankRoutingNumber.isEmpty && !bankAccountNumber.isEmpty && !bankAccountName.isEmpty
        case .stripe: return false // Not implemented yet
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoadingPayout {
                    ProgressView().tint(.white)
                } else {
                    VStack(spacing: 0) {
                        stepIndicator
                        
                        TabView(selection: $currentStep) {
                            amountStep.tag(0)
                            payoutStep.tag(1)
                            confirmStep.tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        
                        navigationButtons
                    }
                }
            }
            .navigationTitle("Cash Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.gray)
                }
            }
        }
        .task { await loadData() }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .alert("Cash Out Submitted!", isPresented: $showingSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("You'll receive $\(String(format: "%.2f", creatorAmount)) via \(activeMethod.displayName) within 3-5 business days.")
        }
    }
    
    // MARK: - Step Indicator
    
    private var stepIndicator: some View {
        let steps = ["Amount", "Payout", "Confirm"]
        return HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { i in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= currentStep ? Color.green : Color.gray.opacity(0.3))
                        .frame(height: 3)
                    Text(steps[i])
                        .font(.system(size: 10, weight: i == currentStep ? .bold : .regular))
                        .foregroundColor(i <= currentStep ? .white : .gray)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    
    // MARK: - Step 1: Amount
    
    private var amountStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Balance display
                VStack(spacing: 4) {
                    Text("Available Balance")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("\(availableCoins) coins")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    Text("$\(String(format: "%.2f", HypeCoinValue.toDollars(availableCoins))) value")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.top, 20)
                
                // Amount input
                VStack(spacing: 8) {
                    TextField("Enter coin amount", text: $cashOutAmount)
                        .keyboardType(.numberPad)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(12)
                    
                    Text("Minimum: \(CashOutLimits.minimumCoins) coins ($\(String(format: "%.2f", HypeCoinValue.toDollars(CashOutLimits.minimumCoins))))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                
                // Quick amounts
                HStack(spacing: 10) {
                    quickAmountButton(1000)
                    quickAmountButton(2500)
                    quickAmountButton(5000)
                    if availableCoins >= 10000 {
                        quickAmountButton(availableCoins, label: "Max")
                    }
                }
                .padding(.horizontal)
                
                // Breakdown
                if coinAmount > 0 {
                    breakdownCard
                }
            }
        }
    }
    
    private func quickAmountButton(_ amount: Int, label: String? = nil) -> some View {
        Button(action: { cashOutAmount = "\(amount)" }) {
            Text(label ?? "\(amount)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(coinAmount == amount ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(coinAmount == amount ? Color.green : Color.gray.opacity(0.2))
                .cornerRadius(8)
        }
    }
    
    private var breakdownCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Your tier")
                    .foregroundColor(.gray)
                Spacer()
                Text(userTier.displayName)
                    .foregroundColor(.purple)
            }
            .font(.system(size: 14))
            
            HStack {
                Text("Revenue share")
                    .foregroundColor(.gray)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(Int(effectiveShare * 100))%")
                        .foregroundColor(.green)
                    if !shareLabel.isEmpty {
                        Text("(\(shareLabel))")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    }
                }
            }
            .font(.system(size: 14))
            
            Divider().background(Color.gray.opacity(0.3))
            
            HStack {
                Text("Platform fee")
                    .foregroundColor(.gray)
                Spacer()
                Text("-$\(String(format: "%.2f", platformAmount))")
                    .foregroundColor(.red.opacity(0.7))
            }
            .font(.system(size: 13))
            
            HStack {
                Text("You'll receive")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("$\(String(format: "%.2f", creatorAmount))")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
        .padding(.horizontal)
    }
    
    // MARK: - Step 2: Payout Method
    
    private var payoutStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Saved method
                if let saved = savedPayoutInfo, saved.isComplete {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Saved Payout Method")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        Button(action: { useSavedMethod = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: saved.methodEnum == .paypal ? "p.circle.fill" : "building.columns.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.cyan)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(saved.methodEnum.displayName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(saved.displaySummary)
                                        .font(.system(size: 13))
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                if useSavedMethod {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(useSavedMethod ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(useSavedMethod ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                            )
                            .cornerRadius(12)
                        }
                        
                        Button(action: { useSavedMethod = false }) {
                            Text("Use different method")
                                .font(.system(size: 13))
                                .foregroundColor(.cyan)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // New method entry
                if savedPayoutInfo == nil || !useSavedMethod {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Choose Payout Method")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        // PayPal option
                        methodSelector(
                            method: .paypal,
                            icon: "p.circle.fill",
                            title: "PayPal",
                            subtitle: "Fastest — usually within 24 hours"
                        )
                        
                        // Bank option
                        methodSelector(
                            method: .bankTransfer,
                            icon: "building.columns.fill",
                            title: "Bank Transfer",
                            subtitle: "Direct deposit — 3-5 business days"
                        )
                        
                        // Details entry
                        if selectedMethod == .paypal {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("PayPal Email")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                                TextField("your@email.com", text: $paypalEmail)
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color.gray.opacity(0.12))
                                    .cornerRadius(10)
                            }
                        } else if selectedMethod == .bankTransfer {
                            VStack(spacing: 12) {
                                bankField(title: "Account Holder Name", text: $bankAccountName, placeholder: "Full legal name")
                                bankField(title: "Routing Number", text: $bankRoutingNumber, placeholder: "9 digits", keyboard: .numberPad)
                                bankField(title: "Account Number", text: $bankAccountNumber, placeholder: "Account number", keyboard: .numberPad)
                            }
                        }
                        
                        // Save toggle
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.square.fill")
                                .foregroundColor(.green)
                            Text("Save this payout method for future withdrawals")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal)
                }
                
                // Tax info reminder
                taxInfoBanner
            }
            .padding(.top, 12)
        }
    }
    
    private func methodSelector(method: PayoutMethod, icon: String, title: String, subtitle: String) -> some View {
        Button(action: { selectedMethod = method }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(selectedMethod == method ? .green : .gray)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if selectedMethod == method {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(14)
            .background(selectedMethod == method ? Color.green.opacity(0.08) : Color.gray.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedMethod == method ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(12)
        }
    }
    
    private func bankField(title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .keyboardType(keyboard)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(10)
        }
    }
    
    private var taxInfoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tax Information")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("US creators earning $600+ annually will receive a 1099 form. Ensure your legal name matches your tax records.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.06))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Step 3: Confirm
    
    private var confirmStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary header
                VStack(spacing: 6) {
                    Text("Confirm Cash Out")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Review your withdrawal details")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .padding(.top, 20)
                
                // Summary card
                VStack(spacing: 12) {
                    confirmRow(label: "Amount", value: "\(coinAmount) coins")
                    confirmRow(label: "Cash Value", value: "$\(String(format: "%.2f", HypeCoinValue.toDollars(coinAmount)))")
                    confirmRow(label: "Revenue Share", value: "\(Int(effectiveShare * 100))%", color: .green)
                    confirmRow(label: "Platform Fee", value: "-$\(String(format: "%.2f", platformAmount))", color: .red.opacity(0.7))
                    
                    Divider().background(Color.gray.opacity(0.3))
                    
                    confirmRow(label: "You Receive", value: "$\(String(format: "%.2f", creatorAmount))", color: .green, bold: true)
                    
                    Divider().background(Color.gray.opacity(0.3))
                    
                    confirmRow(label: "Payout Method", value: activeMethod.displayName)
                    
                    if useSavedMethod, let saved = savedPayoutInfo {
                        confirmRow(label: "Destination", value: saved.displaySummary)
                    } else if selectedMethod == .paypal {
                        confirmRow(label: "PayPal", value: paypalEmail)
                    } else {
                        confirmRow(label: "Bank", value: "****\(String(bankAccountNumber.suffix(4)))")
                    }
                    
                    confirmRow(label: "Estimated Arrival", value: "3-5 business days")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(14)
                .padding(.horizontal)
                
                // Remaining balance
                VStack(spacing: 4) {
                    Text("Remaining Balance")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(availableCoins - coinAmount) coins")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 8)
            }
        }
    }
    
    private func confirmRow(label: String, value: String, color: Color = .white, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: bold ? 18 : 14, weight: bold ? .bold : .semibold))
                .foregroundColor(color)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button(action: { withAnimation { currentStep -= 1 } }) {
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(12)
                }
            }
            
            if currentStep < 2 {
                let canProceed = currentStep == 0 ? isValidAmount : isPayoutComplete
                Button(action: { withAnimation { currentStep += 1 } }) {
                    Text("Next")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(canProceed ? .black : .gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(canProceed ? Color.green : Color.gray.opacity(0.2))
                        .cornerRadius(12)
                }
                .disabled(!canProceed)
            } else {
                Button(action: { processCashOut() }) {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "banknote")
                            Text("Confirm Cash Out")
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.green)
                    .cornerRadius(12)
                }
                .disabled(isProcessing)
            }
        }
        .padding()
        .background(Color.black)
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        isLoadingPayout = true
        
        // Load saved payout info
        do {
            let doc = try await db.collection("users").document(userID)
                .collection("private").document("payoutInfo").getDocument()
            if doc.exists, let info = try? doc.data(as: PayoutInfo.self) {
                await MainActor.run {
                    savedPayoutInfo = info
                    useSavedMethod = info.isComplete
                }
            }
        } catch {
            print("⚠️ CASHOUT: No saved payout info")
        }
        
        // Load effective share (auto-fetches custom override from user doc)
        do {
            let userDoc = try await db.collection("users").document(userID).getDocument()
            if let data = userDoc.data() {
                let customShare = data["customSubShare"] as? Double
                let expiresAt = (data["customSubShareExpiresAt"] as? Timestamp)?.dateValue()
                let permanent = data["customSubSharePermanent"] as? Bool ?? false
                let refCount = data["referralCount"] as? Int ?? 0
                let refGoal = data["referralGoal"] as? Int
                
                let share = SubscriptionRevenueShare.effectiveCreatorShare(
                    tier: userTier,
                    customSubShare: customShare,
                    customSubShareExpiresAt: expiresAt,
                    customSubSharePermanent: permanent,
                    referralCount: refCount,
                    referralGoal: refGoal
                )
                
                await MainActor.run {
                    effectiveShare = share
                    if customShare != nil && share == customShare {
                        shareLabel = "Custom"
                    } else {
                        shareLabel = ""
                    }
                }
            } else {
                await MainActor.run {
                    effectiveShare = SubscriptionRevenueShare.creatorShare(for: userTier)
                }
            }
        } catch {
            await MainActor.run {
                effectiveShare = SubscriptionRevenueShare.creatorShare(for: userTier)
            }
        }
        
        isLoadingPayout = false
    }
    
    // MARK: - Process Cash Out
    
    private func processCashOut() {
        isProcessing = true
        
        Task {
            do {
                // Save payout info if new
                if !useSavedMethod || savedPayoutInfo == nil {
                    let last4 = selectedMethod == .bankTransfer ? String(bankAccountNumber.suffix(4)) : nil
                    let info = PayoutInfo(
                        method: selectedMethod.rawValue,
                        paypalEmail: selectedMethod == .paypal ? paypalEmail : nil,
                        bankAccountName: selectedMethod == .bankTransfer ? bankAccountName : nil,
                        bankRoutingNumber: selectedMethod == .bankTransfer ? bankRoutingNumber : nil,
                        bankAccountNumber: selectedMethod == .bankTransfer ? bankAccountNumber : nil,
                        bankAccountLast4: last4,
                        stripeConnectID: nil,
                        updatedAt: Date()
                    )
                    
                    try db.collection("users").document(userID)
                        .collection("private").document("payoutInfo")
                        .setData(from: info)
                    
                    print("💾 CASHOUT: Payout info saved")
                }
                
                // Process cash out
                _ = try await HypeCoinService.shared.requestCashOut(
                    userID: userID,
                    amount: coinAmount,
                    tier: userTier,
                    payoutMethod: activeMethod
                )
                
                await MainActor.run {
                    isProcessing = false
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - PayoutMethod Extension

extension PayoutMethod {
    var displayName: String {
        switch self {
        case .bankTransfer: return "Bank Transfer"
        case .paypal: return "PayPal"
        case .stripe: return "Stripe"
        }
    }
}