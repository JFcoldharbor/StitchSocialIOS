//
//  MySubscribersView.swift
//  StitchSocial
//
//  CACHING: SubscriptionService.fetchMySubscribers (5min TTL).
//  User profiles batch-fetched via UserService.getUsers(ids:) — single query not N reads.
//

import SwiftUI

struct MySubscribersView: View {

    let creatorID: String

    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var userInfoMap: [String: BasicUserInfo] = [:]
    private let userService = UserService()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(.white)
                } else if subscriptionService.mySubscribers.isEmpty {
                    emptyState
                } else {
                    subscribersList
                }
            }
            .navigationTitle("My Subscribers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.cyan)
                }
            }
        }
        .task { await loadSubscribers() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 50)).foregroundColor(.gray)
            Text("No Subscribers Yet")
                .font(.title3).fontWeight(.bold).foregroundColor(.white)
            Text("When fans subscribe to you, they\'ll appear here.")
                .font(.subheadline).foregroundColor(.gray)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
    }

    // MARK: - List

    private var subscribersList: some View {
        ScrollView {
            summaryBar
            LazyVStack(spacing: 8) {
                ForEach(subscriptionService.mySubscribers) { sub in
                    subscriberRow(sub)
                }
            }
        }
    }

    private var summaryBar: some View {
        let subs = subscriptionService.mySubscribers
        let total = subs.reduce(0) { $0 + ($1.coinsPaid * max(1, $1.renewalCount)) }
        return HStack(spacing: 20) {
            summaryCell(value: "\(subs.count)", label: "Active", color: .cyan)
            summaryCell(value: "\(total)", label: "Coins Earned", color: .yellow)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(14)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func summaryCell(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold)).foregroundColor(color)
            Text(label).font(.caption).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func subscriberRow(_ sub: ActiveSubscription) -> some View {
        let info = userInfoMap[sub.subscriberID]
        let name = info?.displayName ?? "Subscriber"
        let handle = info?.username ?? sub.subscriberID
        let avatar = info?.profileImageURL

        return HStack(spacing: 12) {
            AsyncImage(url: URL(string: avatar ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text("@\(handle)").font(.system(size: 12)).foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(sub.coinsPaid) coins")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.yellow)
                Text(sub.subscribedAt, style: .date)
                    .font(.system(size: 10)).foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Load
    // BATCHING: getUsers(ids:) does one Firestore query for all subscriber profiles

    private func loadSubscribers() async {
        isLoading = true
        let subs = (try? await subscriptionService.fetchMySubscribers(creatorID: creatorID)) ?? []
        let ids = subs.map { $0.subscriberID }
        if let users = try? await userService.getUsers(ids: ids) {
            await MainActor.run {
                userInfoMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            }
        }
        isLoading = false
    }
}
