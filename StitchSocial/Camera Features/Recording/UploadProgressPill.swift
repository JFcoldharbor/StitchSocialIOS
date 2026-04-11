//
//  UploadProgressPill.swift
//  StitchSocial
//
//  Layer 8: Views - Floating Upload Progress Indicator
//  Dependencies: BackgroundPostManager
//  Features: Shows background upload progress, tap to expand, retry on failure
//

import SwiftUI

struct UploadProgressPill: View {
    
    @ObservedObject var postManager = BackgroundPostManager.shared
    @State private var isExpanded = false
    
    var body: some View {
        if postManager.isPosting || postManager.status == .failed {
            VStack(spacing: 0) {
                pillContent
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    }
                
                if isExpanded {
                    expandedContent
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var pillContent: some View {
        HStack(spacing: 10) {
            statusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(postManager.status == .failed ? "Post failed" : "Posting...")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                if postManager.status != .failed {
                    Text(postManager.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if postManager.status == .failed {
                Button("Retry") {
                    postManager.retryFailed()
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.8))
                .clipShape(Capsule())
            } else {
                Text("\(Int(postManager.progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Capsule()
                    .fill(postManager.status == .failed ? Color.red.opacity(0.9) : Color.blue.opacity(0.9))
                
                if postManager.status != .failed {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: geo.size.width * postManager.progress)
                    }
                }
            }
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch postManager.status {
        case .queued:
            Image(systemName: "clock.fill")
                .foregroundColor(.white)
                .font(.system(size: 14))
        case .compressing, .integrating:
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white)
        case .uploading:
            Image(systemName: "arrow.up.circle.fill")
                .foregroundColor(.white)
                .font(.system(size: 14))
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
                .font(.system(size: 14))
        }
    }
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let post = postManager.currentPost {
                HStack {
                    Text(post.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if postManager.status != .failed {
                        Button {
                            postManager.cancelCurrentPost()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 16))
                        }
                    }
                }
            }
            
            if let error = postManager.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.9))
                    .lineLimit(2)
            }
            
            if postManager.postQueue.count > 0 {
                Text("\(postManager.postQueue.count) more in queue")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .padding(.top, 4)
    }
}

struct PostCompletionBanner: View {
    
    @ObservedObject var postManager = BackgroundPostManager.shared
    
    var body: some View {
        if postManager.showCompletionBanner {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Text("Video posted!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                    )
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
