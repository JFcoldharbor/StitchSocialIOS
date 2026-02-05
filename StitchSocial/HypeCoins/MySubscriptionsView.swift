//
//  MySubscriptionsView.swift
//  StitchSocial
//
//  Created by James Garmon on 2/2/26.
//


//
//  MySubscriptionsView.swift
//  StitchSocial
//
//  View for managing user's subscriptions to creators
//

import SwiftUI

struct MySubscriptionsView: View {
    
    // MARK: - Properties
    
    let userID: String
    
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Creator avatar placeholder
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Creator")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    // Tier badge
                    HStack(spacing: 4) {
                        Image(systemName: subscription.tier == .superFan ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        
                        Text(subscription.tier.displayName)
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(4)
                }
                
                Spacer()
                
                // Status
                VStack(alignment: .trailing, spacing: 2) {
                    Circle()
                        .fill(subscription.isActive ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(subscription.isActive ? "Active" : "Expired")
                        .font(.caption)
                        .foregroundColor(subscription.isActive ? .green : .red)
                }
            }
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Details
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscribed")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text(subscription.startedAt, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Renews")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if subscription.renewalEnabled {
                        Text(subscription.expiresAt, style: .date)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    } else {
                        Text("Cancelled")
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Perks
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Perks")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                FlowLayout(spacing: 8) {
                    ForEach(subscription.tier.perks, id: \.self) { perk in
                        HStack(spacing: 4) {
                            Image(systemName: perk.icon)
                                .font(.caption2)
                            Text(perk.displayName)
                                .font(.caption)
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.15))
                        .cornerRadius(4)
                    }
                }
            }
            
            // Cancel button
            if subscription.renewalEnabled {
                Button(action: { showingCancelConfirm = true }) {
                    Text("Cancel Subscription")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.15))
        .cornerRadius(16)
        .alert("Cancel Subscription?", isPresented: $showingCancelConfirm) {
            Button("Keep", role: .cancel) { }
            Button("Cancel", role: .destructive) { onCancel() }
        } message: {
            Text("You'll keep your perks until \(subscription.expiresAt, style: .date)")
        }
    }
}

// MARK: - Flow Layout (for perks)

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