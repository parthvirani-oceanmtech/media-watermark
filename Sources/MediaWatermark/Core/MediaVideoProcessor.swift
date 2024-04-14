//
//  MediaItemVideo.swift
//  MediaWatermark
//
//  Created by Sergei on 03/05/2017.
//  Copyright © 2017 rubygarage. All rights reserved.
//

import UIKit
import AVFoundation

let kMediaContentDefaultScale: CGFloat = 1
let kProcessedTemporaryVideoFileNameExtension = "mp4"
let kMediaContentTimeValue: Int64 = 1
//let kMediaContentTimeScale: Int32 = 30

extension CALayer {
    func toImage() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(bounds.size,false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        render(in: context)
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

extension MediaProcessor {
    func processVideoWithElements(item: MediaItem, outputVideoPath: URL, completion: @escaping ProcessCompletionHandler, progress: ((Double) -> Void)? = nil) {
        let mixComposition = AVMutableComposition()
        let compositionVideoTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let clipVideoTrack = item.sourceAsset.tracks(withMediaType: AVMediaType.video).first
        let clipAudioTrack = item.sourceAsset.tracks(withMediaType: AVMediaType.audio).first
        
        
        do {
            try compositionVideoTrack?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: item.sourceAsset.duration), of: clipVideoTrack!, at: CMTime.zero)
        } catch {
            completion(MediaProcessResult(processedUrl: nil, image: nil), error)
        }
        
        if (clipAudioTrack != nil) {
            let compositionAudioTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            do {
                try compositionAudioTrack?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: item.sourceAsset.duration), of: clipAudioTrack!, at: CMTime.zero)
            } catch {
                completion(MediaProcessResult(processedUrl: nil, image: nil), error)
            }
        }
        
        compositionVideoTrack?.preferredTransform = (item.sourceAsset.tracks(withMediaType: AVMediaType.video).first?.preferredTransform)!
        
        let sizeOfVideo = item.size
        
        //        let optionalLayer = CALayer()
        //        processAndAddElements(item: item, layer: optionalLayer)
        //        optionalLayer.frame = CGRect(x: 0, y: 0, width: sizeOfVideo.width, height: sizeOfVideo.height)
        //
        //
        //        let parentLayer = CALayer()
        //        let videoLayer = CALayer()
        //
        //        parentLayer.frame = CGRect(x: 0, y: 0, width: sizeOfVideo.width, height: sizeOfVideo.height)
        //        videoLayer.frame = CGRect(x: 0, y: 0, width: sizeOfVideo.width, height: sizeOfVideo.height)
        //
        //        parentLayer.addSublayer(videoLayer)
        //        parentLayer.addSublayer(optionalLayer)
        
        let fps = Int32(item.sourceAsset.tracks(withMediaType: .video).first!.nominalFrameRate)
        
        var watermarkElement: UIImage! = nil
        
        for element in item.mediaElements {
            
            if element.type == .view {
                watermarkElement = UIImage(view: element.contentView)
            } else if element.type == .image {
                watermarkElement = element.contentImage
            }
        }
        
        var videoComposition:AVVideoComposition! = nil
        
        if(watermarkElement != nil){
            let watermarkFilter = CIFilter(name: "CISourceOverCompositing")!
            let watermarkImage = CIImage(image: watermarkElement)
            videoComposition = AVVideoComposition(asset: item.sourceAsset) { (filteringRequest) in
                let source = filteringRequest.sourceImage.clampedToExtent()
                watermarkFilter.setValue(source, forKey: "inputBackgroundImage")
                let transform = CGAffineTransform(translationX: filteringRequest.sourceImage.extent.width - (watermarkImage?.extent.width)! - 2, y: 0)
                watermarkFilter.setValue(watermarkImage?.transformed(by: transform), forKey: "inputImage")
                filteringRequest.finish(with: watermarkFilter.outputImage!, context: nil)
            }
        } else{
            videoComposition = AVMutableVideoComposition()
//            videoComposition.frameDuration = CMTimeMake(value: kMediaContentTimeValue, timescale: fps)
//            videoComposition.renderSize = sizeOfVideo
//            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
//            
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: mixComposition.duration)
            
            let videoTrack = mixComposition.tracks(withMediaType: AVMediaType.video).first
            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack!)
            layerInstruction.setTransform(transform(avAsset: item.sourceAsset, scaleFactor: kMediaContentDefaultScale), at: CMTime.zero)
            instruction.layerInstructions = [layerInstruction]
//            videoComposition.instructions = [instruction]
        }
        
        let processedUrl = processedMoviePath()
        clearTemporaryData(url: processedUrl, completion: completion)
        
        let exportSession = AVAssetExportSession(asset: item.sourceAsset, presetName: AVAssetExportPresetHighestQuality)
        guard let exportSession = exportSession else { return }
        exportSession.videoComposition = videoComposition
        exportSession.outputURL = processedUrl
        exportSession.outputFileType = AVFileType.mp4
        
        if progressTimer == nil {
            self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                self.progressCallbacks.forEach { key, value in
                    value(Double(key.progress))
                }
            }
        }
        
        exportSession.exportAsynchronously(completionHandler: { [weak self] in
            self?.exportSessions.removeAll { $0 == exportSession }
            self?.progressCallbacks[exportSession] = nil
            if self?.progressCallbacks.isEmpty ?? false {
                self?.clearTimer()
            }
            if exportSession.status == AVAssetExportSession.Status.completed {
                completion(MediaProcessResult(processedUrl: processedUrl, image: nil), nil)
            } else {
                completion(MediaProcessResult(processedUrl: nil, image: nil), exportSession.error)
            }
        })
        progressCallbacks[exportSession] = progress
        exportSessions.append(exportSession)
    }
    
    func clearTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    public func cancelExport() {
        exportSessions.forEach { $0.cancelExport() }
        clearTimer()
    }
    
    // MARK: - private
    private func processAndAddElements(item: MediaItem, layer: CALayer) {
        for element in item.mediaElements {
            var elementLayer: CALayer! = nil
            
            if element.type == .view {
                elementLayer = CALayer()
                elementLayer.contents = UIImage(view: element.contentView).cgImage
            } else if element.type == .image {
                elementLayer = CALayer()
                elementLayer.contents = element.contentImage.cgImage
            } else if element.type == .text {
                elementLayer = CATextLayer()
                (elementLayer as! CATextLayer).string = element.contentText
            }
            
            elementLayer.frame = element.frame
            layer.addSublayer(elementLayer)
        }
    }
    
    private func processedMoviePath() -> URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/" + UUID().uuidString + "." + kProcessedTemporaryVideoFileNameExtension
        return URL(fileURLWithPath: documentsPath)
    }
    
    private func clearTemporaryData(url: URL, completion: ProcessCompletionHandler!) {
        if (FileManager.default.fileExists(atPath: url.path)) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                completion(MediaProcessResult(processedUrl: nil, image: nil), error)
            }
        }
    }
    
    private func transform(avAsset: AVAsset, scaleFactor: CGFloat) -> CGAffineTransform {
        var offset = CGPoint.zero
        var angle: Double = 0
        
        switch avAsset.contentOrientation {
        case .left:
            offset = CGPoint(x: avAsset.contentCorrectSize.height, y: avAsset.contentCorrectSize.width)
            angle = Double.pi
        case .right:
            offset = CGPoint.zero
            angle = 0
        case .down:
            offset = CGPoint(x: 0, y: avAsset.contentCorrectSize.width)
            angle = -(Double.pi / 2)
        default:
            offset = CGPoint(x: avAsset.contentCorrectSize.height, y: 0)
            angle = Double.pi / 2
        }
        
        let scale = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
        let translation = scale.translatedBy(x: offset.x, y: offset.y)
        let rotation = translation.rotated(by: CGFloat(angle))
        
        return rotation
    }
}
