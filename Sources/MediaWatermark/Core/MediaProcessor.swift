//
//  MediaProcessor.swift
//  MediaWatermark
//
//  Created by Sergei on 23/05/2017.
//  Copyright © 2017 rubygarage. All rights reserved.
//

import Foundation
import AVFoundation

public class MediaProcessor {
    internal var exportSessions: [AVAssetExportSession] = []
    internal var progressCallbacks: [AVAssetExportSession: (Double) -> Void] = [:]
    internal var progressTimer: Timer? = nil
    public var filterProcessor: FilterProcessor! = nil
    
    public init() {}
    deinit {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    // MARK: - process elements
    public func processElements(item: MediaItem, outputVideoPath: URL, completion: @escaping ProcessCompletionHandler, progress: ((Double) -> Void)? = nil) {
        item.type == .video ? processVideoWithElements(item: item,outputVideoPath:outputVideoPath, completion: completion, progress: progress) : processImageWithElements(item: item, completion: completion, progress: progress)
    }
}
