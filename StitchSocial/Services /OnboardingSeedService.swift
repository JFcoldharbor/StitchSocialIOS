//
//  OnboardingSeedService.swift
//  StitchSocial
//
//  Created by James Garmon on 3/24/26.
//


//
//  OnboardingSeedService.swift
//  StitchSocial
//
//  Layer 4: Services - Onboarding seed video fetch + cache
//  Dependencies: VideoService, FirebaseFirestore
//
//  CACHING:
//  - Firestore reads: 2 total, ever, per install
//      1. app_config/onboarding  → get seedVideoID
//      2. videos/{seedVideoID}   → get CoreVideoMetadata
//  - Both results written to UserDefaults immediately after first fetch
//  - Subsequent calls return from UserDefaults — zero Firestore reads
//  - Cache survives app restarts until onboarding completes or app reinstall
//
//  BATCHING: N/A — only 2 reads ever, not worth batching
//
//  ADD TO CachingOptimization.swift:
//  "OnboardingSeedService — UserDefaults keys:
//     'onboarding_seed_video_id'   (String)
//     'onboarding_seed_video_data' (Data — JSON-encoded CoreVideoMetadata)
//   2 Firestore reads total, ever. Reads app_config/onboarding for the ID,
//   then videos/{id} for the metadata. Both cached permanently until
//   onboarding completes (OnboardingState.complete() clears them) or reinstall."
//
//  FIRESTORE SETUP:
//  Create this document manually in the Firebase console:
//    Collection : app_config
//    Document   : onboarding
//    Fields     :
//      seedVideoID : String   ← paste the video ID you want here
//      updatedAt   : Timestamp
//
//  To swap the seed video, update seedVideoID in the console.
//  Clear the UserDefaults cache key 'onboarding_seed_video_id' in a
//  new app build if you want existing users to pick up the new seed.
//  (New installs always fetch fresh.)
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - OnboardingSeedService

@MainActor
final class OnboardingSeedService {

    static let shared = OnboardingSeedService()
    private init() {}

    // MARK: - Cache Keys

    private enum Keys {
        static let videoID   = "onboarding_seed_video_id"
        static let videoData = "onboarding_seed_video_data"
    }

    // MARK: - Firestore

    private let db = Firestore.firestore(database: Config.Firebase.databaseName)
    private let videoService = VideoService()

    // MARK: - Public API

    /// Returns the seed video, using UserDefaults cache when available.
    /// On first call: 2 Firestore reads. All subsequent calls: 0 reads.
    func fetchSeedVideo() async -> CoreVideoMetadata? {

        // 1. Return cached video if available
        if let cached = loadFromCache() {
            print("✅ SEED: Returning cached seed video '\(cached.title)'")
            return cached
        }

        // 2. Fetch seed video ID from app_config/onboarding
        guard let videoID = await fetchSeedVideoID() else {
            print("⚠️ SEED: No seedVideoID found in app_config/onboarding")
            return nil
        }

        // 3. Fetch video metadata
        do {
            let video = try await videoService.getVideo(id: videoID)
            saveToCache(video)
            print("✅ SEED: Fetched and cached seed video '\(video.title)' (replyCount: \(video.replyCount))")
            return video
        } catch {
            print("❌ SEED: Failed to fetch seed video \(videoID): \(error)")
            return nil
        }
    }

    /// Call when onboarding completes — clears cache so it doesn't persist forever
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: Keys.videoID)
        UserDefaults.standard.removeObject(forKey: Keys.videoData)
        print("🧹 SEED: Cache cleared")
    }

    // MARK: - Private: Firestore Fetch

    private func fetchSeedVideoID() async -> String? {
        do {
            let doc = try await db
                .collection("app_config")
                .document("onboarding")
                .getDocument()

            guard doc.exists, let videoID = doc.data()?["seedVideoID"] as? String,
                  !videoID.isEmpty else {
                print("⚠️ SEED: app_config/onboarding missing or seedVideoID empty")
                return nil
            }

            // Cache the ID so we don't re-read app_config next time
            UserDefaults.standard.set(videoID, forKey: Keys.videoID)
            print("✅ SEED: Got seedVideoID '\(videoID)' from Firestore")
            return videoID

        } catch {
            print("❌ SEED: Failed to read app_config/onboarding: \(error)")
            return nil
        }
    }

    // MARK: - Private: UserDefaults Cache

    private func loadFromCache() -> CoreVideoMetadata? {
        guard UserDefaults.standard.string(forKey: Keys.videoID) != nil,
              let data = UserDefaults.standard.data(forKey: Keys.videoData) else {
            return nil
        }
        return try? JSONDecoder().decode(CoreVideoMetadata.self, from: data)
    }

    private func saveToCache(_ video: CoreVideoMetadata) {
        guard let data = try? JSONEncoder().encode(video) else { return }
        UserDefaults.standard.set(video.id, forKey: Keys.videoID)
        UserDefaults.standard.set(data, forKey: Keys.videoData)
    }
}