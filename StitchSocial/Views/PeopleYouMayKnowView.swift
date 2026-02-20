//
//  PeopleYouMayKnowView.swift
//  StitchSocial
//
//  Layer 8: Views - People You May Know Sheet
//  Dependencies: SuggestionService, PrivacyService
//  Features: Mutual follower suggestions, inline follow, profile pics
//
//  CACHING: Uses SuggestionService session cache (10 min TTL).
//  First open: 1 read if pre-computed, N+1 if fallback.
//  Subsequent opens within 10 min: 0 reads.
//

import SwiftUI

struct PeopleYouMayKnowView: View {
    
    let userID: String
    
    @StateObject private var suggestionService = SuggestionService()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if suggestionService.isMutualLoading && !suggestionService.hasMutualLoaded {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                            .scaleEffect(1.2)
                        Text("Finding people you may know...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                } else if suggestionService.mutualSuggestions.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(suggestionService.mutualSuggestions) { suggestion in
                                suggestionRow(suggestion)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("People You May Know")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.cyan)
                }
            }
            .task {
                await suggestionService.loadMutualSuggestions(userID: userID)
            }
        }
    }
    
    // MARK: - Suggestion Row
    
    private func suggestionRow(_ suggestion: UserSuggestion) -> some View {
        HStack(spacing: 14) {
            // Profile pic
            AsyncImage(url: URL(string: suggestion.profileImageURL ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 18))
                    )
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.displayName.isEmpty ? suggestion.username : suggestion.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if !suggestion.username.isEmpty {
                    Text("@\(suggestion.username)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                // Mutual info
                mutualLabel(suggestion)
            }
            
            Spacer()
            
            // Follow button
            Button(action: {
                Task {
                    await suggestionService.followSuggestedUser(suggestion.id, currentUserID: userID)
                }
            }) {
                Text(suggestion.isFollowed ? "Following" : "Follow")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(suggestion.isFollowed ? .gray : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(suggestion.isFollowed ? Color.gray.opacity(0.2) : Color.cyan)
                    )
            }
            .disabled(suggestion.isFollowed)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Mutual Label
    
    private func mutualLabel(_ suggestion: UserSuggestion) -> some View {
        Group {
            if suggestion.mutualCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan.opacity(0.7))
                    
                    if let firstName = suggestion.mutualNames.first {
                        if suggestion.mutualCount == 1 {
                            Text("Followed by \(firstName)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        } else {
                            Text("Followed by \(firstName) + \(suggestion.mutualCount - 1) more")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    } else {
                        Text("\(suggestion.mutualCount) mutual connections")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No suggestions yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Follow more people to unlock mutual connection suggestions")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
