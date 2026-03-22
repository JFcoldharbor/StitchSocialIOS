//
//  MySubscriptionsView.swift
//  StitchSocial
//
//  View for managing user's active subscriptions to creators.
//  Shows creator info, days remaining, cycle type, perks, cancel option.
//
//  CACHING: Reads from SubscriptionService's mySubsCache (5min TTL).
//  Creator info fetched per-card — could batch in future if list grows.
//

import SwiftUI

struct MySubscriptionsView: View {
    
    let userID: String
    
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView().tint(.white)
                } else if subscriptionService.mySubscriptions.isEmpty {
                    emptyState
                } else {
                    subscriptionsList
                }
            }
            .navigationTitle("My Subscriptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
        }
        .task {
            await loadSubscriptions()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No Subscriptions")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Subscribe to your favorite creators to support them and unlock exclusive perks.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Subscriptions List
    
    private var subscriptionsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(subscriptionService.mySubscriptions) { subscription in
                    SubscriptionCard(subscription: subscription) {
                        cancelSubscription(subscription)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func loadSubscriptions() async {
        isLoading = true
        do {
            _ = try await subscriptionService.fetchMySubscriptions(userID: userID)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
        isLoading = false
    }
    
    private func cancelSubscription(_ subscription: ActiveSubscription) {
        Task {
            do {
                try await subscriptionService.cancelSubscription(
                    subscriberID: userID,
                    creatorID: subscription.creatorID
                )
                await loadSubscriptions()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - Subscription Card

struct SubscriptionCard: View {
    let subscription: ActiveSubscription
    let onCancel: () -> Void
    
    @State private var showingCancelConfirm = false
    @State private var creatorName: String = "Creator"
    @State private var creatorImageURL: String?
    
    /// Perks come from the subscription doc's grantedPerks field
    private var perks: [SubscriptionPerk] {
        subscription.perks
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header — creator info + status
            HStack {
                AsyncImage(url: URL(string: creatorImageURL ?? "")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Text(String(creatorName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(creatorName)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("\(subscription.coinsPaid) coins/month")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }
                
                Spacer()
                
                // Status + days remaining
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(subscription.isActive ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(subscription.isActive ? "Active" : "Expired")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(subscription.isActive ? .green : .red)
                    }
                    
                    if subscription.isActive {
                        Text("\(subscription.daysRemaining)d left")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Divider().background(Color.gray.opacity(0.2))
            
            // Dates row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Started")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(subscription.subscribedAt, style: .date)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .center, spacing: 2) {
                    Text("Cycle")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Text(subscription.renewalCount == 0 ? "60-day trial" : "30-day")
                        .font(.system(size: 12))
                        .foregroundColor(subscription.renewalCount == 0 ? .green : .white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Renews")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    if subscription.autoRenew {
                        Text(subscription.currentPeriodEnd, style: .date)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    } else {
                        Text("Cancelled")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Perks
            if !perks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your Perks")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    
                    FlowLayout(spacing: 6) {
                        ForEach(perks, id: \.self) { perk in
                            HStack(spacing: 3) {
                                Image(systemName: perk.icon)
                                    .font(.system(size: 9))
                                Text(perk.displayName)
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            
            // Cancel button
            if subscription.autoRenew {
                Button(action: { showingCancelConfirm = true }) {
                    Text("Cancel Subscription")
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(14)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
        .task {
            await loadCreatorInfo()
        }
        .alert("Cancel Subscription?", isPresented: $showingCancelConfirm) {
            Button("Keep", role: .cancel) { }
            Button("Cancel", role: .destructive) { onCancel() }
        } message: {
            Text("You'll keep perks until \(subscription.currentPeriodEnd, style: .date)")
        }
    }
    
    private func loadCreatorInfo() async {
        do {
            let doc = try await FirebaseConfig.firestore
                .collection("users")
                .document(subscription.creatorID)
                .getDocument()
            
            if let data = doc.data() {
                await MainActor.run {
                    creatorName = data["displayName"] as? String ?? "Creator"
                    creatorImageURL = data["profileImageURL"] as? String
                }
            }
        } catch {
            print("⚠️ SUB CARD: Failed to load creator info")
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }
        
        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
