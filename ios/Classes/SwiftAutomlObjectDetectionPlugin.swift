import Flutter
import UIKit
import MLKitObjectDetection
import MLKitVision

public class SwiftAutomlObjectDetectionPlugin: NSObject, FlutterPlugin {
    private let registrar: FlutterPluginRegistrar
    
    private var lastDetectorId = 0
    private var detectors = Dictionary<Int, ObjectDetector>()
    private var detectorBitmapSizes = Dictionary<Int, CGSize>()
    private var detectorBitmaps = Dictionary<Int, UnsafeMutableBufferPointer<UInt8>>()
    private var detectorQueues = Dictionary<Int, DispatchQueue>()
    
    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "dev.sonerik.automl_object_detection", binaryMessenger: registrar.messenger())
        let instance = SwiftAutomlObjectDetectionPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "prepareDetector":
            let args = call.arguments as! Dictionary<String, Any?>
            
            let bitmapWidth = args["bitmapWidth"] as! Int
            let bitmapHeight = args["bitmapHeight"] as! Int

            let enableClassification = args["enableClassification"] as! Bool
            let enableMultipleObjects = args["enableMultipleObjects"] as! Bool

            let id = initDetector(
                bitmapSize: CGSize(width: bitmapWidth, height: bitmapHeight),
                enableClassification: enableClassification,
                enableMultipleObjects: enableMultipleObjects
            );
            
            result(id)
        case "disposeDetector":
            let args = call.arguments as! Dictionary<String, Any?>
            let id = args["id"] as! Int
            disposeDetector(id: id)
            result(nil)
        case "processImage":
            let args = call.arguments as! Dictionary<String, Any?>
            let id = args["detectorId"] as! Int
            let imageRgbBytes = args["rgbBytes"] as! FlutterStandardTypedData
            let size = detectorBitmapSizes[id]!
            let detector = detectors[id]!
            var pixels = detectorBitmaps[id]!
            detectorQueues[id]!.async {
                imageRgbBytes.data.withUnsafeBytes {
                    var bytes = $0
                    writeRgbByteArrayToBitmap(rgbBytes: &bytes, argbBitmap: &pixels)
                }
                
                let uiImage = imageFromARGB32Bitmap(pixels: &pixels, width: Int(size.width), height: Int(size.height))!
                let image = VisionImage(image: uiImage)
                detector.process(image) { detectedObjects, error in
                    guard error == nil, let detectedObjects = detectedObjects, !detectedObjects.isEmpty else {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "", message: error?.localizedDescription, details: nil))
                        }
                        return
                    }
                    
                    var resultData = [Dictionary<String, Any?>]()
                    for obj in detectedObjects {
                        resultData.append([
                            "trackingId": obj.trackingID,
                            "boundingBox": [
                                "left": obj.frame.minX,
                                "top": obj.frame.minY,
                                "right": obj.frame.maxX,
                                "bottom": obj.frame.maxY
                            ],
                            "labels": obj.labels.map {
                                [
                                    "index": $0.index,
                                    "text": $0.text,
                                    "confidence": $0.confidence
                                ]
                            }
                        ])
                    }
                    
                    DispatchQueue.main.async {
                        result(resultData)
                    }
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func initDetector(
        bitmapSize: CGSize,
        enableClassification: Bool,
        enableMultipleObjects: Bool
    ) -> Int {
        let id = lastDetectorId
        lastDetectorId += 1
        
        let queue = DispatchQueue(label: "MLKit ObjectDetector #\(id)", qos: .userInteractive)

        // Multiple object detection in static images
        let detectorOptions = ObjectDetectorOptions()
        detectorOptions.detectorMode = .stream
        if (enableClassification) {
            detectorOptions.shouldEnableClassification = true
        }
        if (enableMultipleObjects) {
            detectorOptions.shouldEnableMultipleObjects = true
        }

        let detector = ObjectDetector.objectDetector(options: detectorOptions)
        
        detectors[id] = detector
        detectorQueues[id] = queue
        detectorBitmapSizes[id] = bitmapSize
        detectorBitmaps[id] = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(bitmapSize.width * bitmapSize.height * 4))
        
        return id
    }
    
    private func disposeDetector(id: Int) {
        detectors.removeValue(forKey: id)
        detectorQueues.removeValue(forKey: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            self.detectorBitmapSizes.removeValue(forKey: id)
            self.detectorBitmaps[id]?.deallocate()
            self.detectorBitmaps.removeValue(forKey: id)
        })
    }
}

private func imageFromARGB32Bitmap(pixels: inout UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int) -> UIImage? {
    guard width > 0 && height > 0 else { return nil }
    guard pixels.count == width * height * 4 else { return nil }
    
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    let bitsPerComponent = 8
    let bitsPerPixel = 32
    
    guard let providerRef = CGDataProvider(
        data: NSData(bytesNoCopy: pixels.baseAddress!, length: pixels.count, deallocator: { (UnsafeMutableRawPointer, Int) in })
    )
    else { return nil }
    
    guard let cgim = CGImage(
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bitsPerPixel: bitsPerPixel,
        bytesPerRow: width * 4,
        space: rgbColorSpace,
        bitmapInfo: bitmapInfo,
        provider: providerRef,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
    )
    else { return nil }
    
    return UIImage(cgImage: cgim)
}

private func writeRgbByteArrayToBitmap(rgbBytes: inout UnsafeRawBufferPointer, argbBitmap: inout UnsafeMutableBufferPointer<UInt8>) {
    let nrOfPixels: Int = rgbBytes.count / 3 // Three bytes per pixel
    if (nrOfPixels > argbBitmap.count) {
        return
    }
    var colorIndex = 0
    for i in (0..<nrOfPixels) {
        let r = 0xFF & rgbBytes[3 * i]
        let g = 0xFF & rgbBytes[3 * i + 1]
        let b = 0xFF & rgbBytes[3 * i + 2]
        
        argbBitmap[colorIndex] = 255
        argbBitmap[colorIndex + 1] = r
        argbBitmap[colorIndex + 2] = g
        argbBitmap[colorIndex + 3] = b
        
        colorIndex += 4
    }
}
