//
//  JZLocationConverter.swift
//  JZLocationConverter-Swift
//
//  Created by jack zhou on 21/07/2017.
//  Copyright © 2017 Jack. All rights reserved.
//

import Foundation
import CoreLocation
extension CLLocationCoordinate2D {
    struct JZConstant {
        static let A = 6378245.0
        static let EE = 0.00669342162296594323
    }
    func gcj02Offset() -> CLLocationCoordinate2D {
        let x = self.longitude - 105.0
        let y = self.latitude - 35.0
        let latitude = (-100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(fabs(x))) +
                        ((20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0) +
                            ((20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0) +
                                ((160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0)
        let longitude = (300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(fabs(x))) +
                            ((20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0) +
                                ((20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0) +
                                    ((150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0)
        let radLat = 1 - self.latitude / 180.0 * .pi;
        var magic = sin(radLat);
        magic = 1 - JZConstant.EE * magic * magic
        let sqrtMagic = sqrt(magic);
        let dLat = (latitude * 180.0) / ((JZConstant.A * (1 - JZConstant.EE)) / (magic * sqrtMagic) * .pi);
        let dLon = (longitude * 180.0) / (JZConstant.A / sqrtMagic * cos(radLat) * .pi);
        return CLLocationCoordinate2DMake(dLat, dLon);
    }
}

open class JZLocationConverter {
    
    fileprivate let queue = DispatchQueue(label: "JZ.LocationConverter.Converter")
    public static let `default`: JZLocationConverter = {
        return JZLocationConverter()
    }()
    
    public static func start(filePath:String!,finished:((_ error:JZFileError?) -> Void)?) {
        JZAreaManager.start(filePath: filePath, finished: finished)
    }
    
    public static func start(finished:((_ error:JZFileError?) -> Void)?) {
        JZAreaManager.start(finished: finished)
    }


}

//GCJ02
extension JZLocationConverter {
    fileprivate func gcj02Encrypt(_ wgs84Point:CLLocationCoordinate2D,result:@escaping (_ gcj02Point:CLLocationCoordinate2D) -> Void) {
        self.queue.async {
            let offsetPoint = wgs84Point.gcj02Offset()
            let resultPoint = CLLocationCoordinate2DMake(wgs84Point.latitude + offsetPoint.latitude, wgs84Point.longitude + offsetPoint.longitude)
            JZAreaManager.default.isOutOfArea(gcj02Point: resultPoint, result: { (isOut:Bool) in
                DispatchQueue.main.async {
                    if isOut {
                        result(wgs84Point)
                    } else {
                        result(resultPoint)
                    }
                }
            })
        }
    }
   
    // As this function call isOutOfArea and then gcj02Encrypt, isOutOfArea which is the most time consuming function will call twice
    fileprivate func gcj02Decrypt(_ gcj02Point:CLLocationCoordinate2D,result:@escaping (_ wgs84Point:CLLocationCoordinate2D) -> Void) {
        JZAreaManager.default.isOutOfArea(gcj02Point: gcj02Point, result: { (isOut:Bool) in
            if isOut {
                DispatchQueue.main.async {
                    result(gcj02Point)
                }
            }else {
                self.gcj02Encrypt(gcj02Point) { (mgPoint:CLLocationCoordinate2D) in
                    self.queue.async {
                        let resultPoint = CLLocationCoordinate2DMake(gcj02Point.latitude * 2 - mgPoint.latitude,gcj02Point.longitude * 2 - mgPoint.longitude)
                        DispatchQueue.main.async {
                            result(resultPoint)
                        }
                    }
                }
            }
        })
    }
   
    // WGS-84 to GCJ-02
    fileprivate func gcj02EncryptPointsAsync(_ wgs84Points: [JZLocationResult], conversionType: JZConversionType, result: @escaping ([JZLocationResult]) -> Void) {
        self.queue.async { [weak self] in
            guard let self else { return DispatchQueue.main.async { result(wgs84Points) } }
            
            // As checking function is using GCJ-02, change WGS-84 to GCJ-02 first
            let gcj02Points = self.WGS84ToGCJ02(points: wgs84Points, isReverse: false)
            
            // Force conversion, bypass isPointsOutOfArea checking, directly return result with GCJ-02
            guard !conversionType.isForceConversion else {
                return DispatchQueue.main.async { result(gcj02Points) }
            }
            
            // Only apply offset if point inside area
            JZAreaManager.default.isPointsOutOfAreaAsync(gcj02Locations: gcj02Points, result: { [weak self] isPointsOutOfAreaResult in
                guard let self else { return DispatchQueue.main.async { result(wgs84Points) } }
                
                let resultPoints = convertWGS84ToGCJ02Result(isPointsOutOfAreaResult: isPointsOutOfAreaResult, wgs84Points: wgs84Points)
                DispatchQueue.main.async { result(resultPoints) }
            })
        }
    }
    
    fileprivate func gcj02EncryptPoints(_ wgs84Points:[JZLocationResult], conversionType: JZConversionType) -> [JZLocationResult] {
        // As checking function is using GCJ-02, change WGS-84 to GCJ-02 first
        let gcj02Points = WGS84ToGCJ02(points: wgs84Points, isReverse: false)
        
        // Force conversion, bypass isPointsOutOfArea checking, directly return result with GCJ-02
        guard !conversionType.isForceConversion else { return gcj02Points }
        
        // Only apply offset if point inside area
        let isPointsOutOfAreaResult = JZAreaManager.default.isPointsOutOfArea(gcj02Locations: gcj02Points)
        return convertWGS84ToGCJ02Result(isPointsOutOfAreaResult: isPointsOutOfAreaResult, wgs84Points: wgs84Points)
    }
   
   
    /// Function for conversion between GCJ02 and WGS84
    /// - Parameters:
    ///   - points: If isReverse is false, input JZLocationResult in type WGS84 else GCJ02.
    ///   - isReverse: If isReverse is true, convrt from GCJ02 to WGS84
    /// - Returns: If isReverse is false, return JZLocationResult in type GCJ02 else WGS84
    private func WGS84ToGCJ02(points: [JZLocationResult], isReverse: Bool) -> [JZLocationResult] {
        return points.map { point in
            let offset = point.coordinate.gcj02Offset()
            let latitude = isReverse ? point.coordinate.latitude - offset.latitude : point.coordinate.latitude + offset.latitude
            let longitude = isReverse ? point.coordinate.longitude - offset.longitude : point.coordinate.longitude + offset.longitude
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return JZLocationResult(type: isReverse ? .WGS84 : .GCJ02 , coordinate: coordinate, isOutOfArea: point.isOutOfArea)
        }
    }
    
    /// Function to generate WGS84 or GCJ02 result of "WGS84 to GCJ02 conversion"
    /// - Parameters:
    ///   - isPointsOutOfAreaResult: Result of isPointsOutOfArea, point.type should be GCJ02.
    ///   - wgs84Points: JZLocationResult, point.type should be WGS84.
    /// - Returns: JZLocationResult, point.type could be WGS84 or GCJ02.
    private func convertWGS84ToGCJ02Result(isPointsOutOfAreaResult: [JZLocationResult], wgs84Points: [JZLocationResult]) -> [JZLocationResult] {
        var resultPoints: [JZLocationResult] = []
        for (index, gcj02Location) in isPointsOutOfAreaResult.enumerated() {
            var wgs84Point = wgs84Points[index]
            
            // Safe check: not expected to be nil
            guard let isOutOfArea = gcj02Location.isOutOfArea else {
                resultPoints.append(wgs84Point)
                continue
            }
            
            // Safe check: only convert coordinate of WGS-84
            if wgs84Point.type != .WGS84 {
                resultPoints.append(wgs84Point)
            }
            else if !isOutOfArea {
                resultPoints.append(gcj02Location)
            } else {
                wgs84Point.isOutOfArea = true
                resultPoints.append(wgs84Point)
            }
        }
        return resultPoints
    }

    // GCJ-02 to WGS-84
    fileprivate func gcj02DecryptPointsAsync(_ gcj02Points:[JZLocationResult], conversionType: JZConversionType, result:@escaping ([JZLocationResult]) -> Void) {
        self.queue.async { [weak self] in
            guard let self else { return DispatchQueue.main.async { result(gcj02Points) } }
            
            guard !conversionType.isForceConversion else {
                let resultPoints = self.WGS84ToGCJ02(points: gcj02Points, isReverse: true)
                return DispatchQueue.main.async { result(resultPoints) }
            }
            
            // Check if points inside area, only apply offset if point inside area
            JZAreaManager.default.isPointsOutOfAreaAsync(gcj02Locations: gcj02Points) { [weak self] isPointsOutOfAreaResult in
                guard let self else { return DispatchQueue.main.async { result(gcj02Points) } }
                
                let resultPoints = self.convertGCJ02ToWGS84Result(isPointsOutOfAreaResult: isPointsOutOfAreaResult, gcj02Points: gcj02Points)
                DispatchQueue.main.async { result(resultPoints) }
            }
        }
    }
    
    fileprivate func gcj02DecryptPoints(_ gcj02Points:[JZLocationResult], conversionType: JZConversionType) -> [JZLocationResult] {
        guard !conversionType.isForceConversion else {
            return self.WGS84ToGCJ02(points: gcj02Points, isReverse: true)
        }
        
        // Check if points inside area, only apply offset if point inside area
        let isPointsOutOfAreaResult = JZAreaManager.default.isPointsOutOfArea(gcj02Locations: gcj02Points)
        return convertGCJ02ToWGS84Result(isPointsOutOfAreaResult: isPointsOutOfAreaResult, gcj02Points: gcj02Points)
    }
    
    /// Function to generate WGS84 or GCJ02 result of "WGS84 to GCJ02 conversion"
    /// - Parameters:
    ///   - isPointsOutOfAreaResult: Result of isPointsOutOfArea, point.type should be GCJ02.
    ///   - gcj02Points: JZLocationResult, original point for conversion. Point.type should be GCJ02.
    /// - Returns: JZLocationResult, point.type could be WGS84 or GCJ02.
    private func convertGCJ02ToWGS84Result(isPointsOutOfAreaResult: [JZLocationResult], gcj02Points:[JZLocationResult]) -> [JZLocationResult] {
        var resultPoints: [JZLocationResult] = []
        for (index, gcj02Location) in isPointsOutOfAreaResult.enumerated() {
            // Safe check: not expected to be nil
            guard let isOutOfArea = gcj02Location.isOutOfArea else {
                resultPoints.append(gcj02Points[index])
                continue
            }
            
            // Safe check: only convert coordinate of GCJ-02
            if gcj02Location.type != .GCJ02 {
                resultPoints.append(gcj02Points[index])
            } else if !isOutOfArea, let wgs84Point = WGS84ToGCJ02(points: [gcj02Location], isReverse: true).first {
                resultPoints.append(wgs84Point)
            } else {
                resultPoints.append(gcj02Location)
            }
        }
        return resultPoints
    }
}

//BD09
extension JZLocationConverter {
    fileprivate func bd09Encrypt(_ gcj02Point:CLLocationCoordinate2D,result:@escaping (_ bd09Point:CLLocationCoordinate2D) -> Void) {
        self.queue.async {
            let x = gcj02Point.longitude
            let y = gcj02Point.latitude
            let z = sqrt(x * x + y * y) + 0.00002 * sin(y * .pi);
            let theta = atan2(y, x) + 0.000003 * cos(x * .pi);
            let resultPoint = CLLocationCoordinate2DMake(z * sin(theta) + 0.006, z * cos(theta) + 0.0065)
            DispatchQueue.main.async {
                result(resultPoint)
            }
        }
    }

    fileprivate func bd09Decrypt(_ bd09Point:CLLocationCoordinate2D,result:@escaping (_ gcj02Point:CLLocationCoordinate2D) -> Void) {
        self.queue.async {
            let x = bd09Point.longitude - 0.0065
            let y = bd09Point.latitude - 0.006
            let z = sqrt(x * x + y * y) - 0.00002 * sin(y * .pi);
            let theta = atan2(y, x) - 0.000003 * cos(x * .pi);
            let resultPoint = CLLocationCoordinate2DMake(z * sin(theta), z * cos(theta))
            DispatchQueue.main.async {
                result(resultPoint)
            }
        }
    }
   
//    // GCJ-02 to BD-09
//    fileprivate func bd09EncryptPoints(_ gcj02Points:[JZLocationResult],result:@escaping ([JZLocationResult]) -> Void) {
//        self.queue.async {
//            var resultPoints: [JZLocationResult] = []
//            for gcj02Point in gcj02Points {
//                let x = gcj02Point.longitude
//                let y = gcj02Point.latitude
//                let z = sqrt(x * x + y * y) + 0.00002 * sin(y * .pi);
//                let theta = atan2(y, x) + 0.000003 * cos(x * .pi);
//                let coordinate = CLLocationCoordinate2DMake(z * sin(theta) + 0.006, z * cos(theta) + 0.0065)
//                let result = JZLocationResult(type: .BD09, coordinate: coordinate)
//                resultPoints.append(result)
//            }
//            DispatchQueue.main.async {
//                result(resultPoints)
//            }
//        }
//    }
//    
//    // This function did not check is inside area and will directly change from BD-09 to GCJ-02 which may not be expected.
//    // Hence, this function is comment out.
//    // BD-09 to GCJ-02
//    fileprivate func bd09DecryptPoints(_ bd09Points:[JZLocationResult],result:@escaping ([JZLocationResult]) -> Void) {
//        self.queue.async {
//            var resultPoints: [JZLocationResult] = []
//            for bd09Point in bd09Points {
//                let x = bd09Point.longitude - 0.0065
//                let y = bd09Point.latitude - 0.006
//                let z = sqrt(x * x + y * y) - 0.00002 * sin(y * .pi);
//                let theta = atan2(y, x) - 0.000003 * cos(x * .pi);
//                let coordinate = CLLocationCoordinate2DMake(z * sin(theta), z * cos(theta))
//                let result = JZLocationResult(type: .GCJ02, coordinate: coordinate)
//                resultPoints.append(result)
//            }
//            DispatchQueue.main.async {
//                result(resultPoints)
//            }
//        }
//    }
   
    private func convertCoordinateToResult(type: JZLocationType, coordinates: [CLLocationCoordinate2D]) -> [JZLocationResult] {
        return coordinates.map { coordinate in
            return JZLocationResult(type: type, coordinate: coordinate)
        }
    }
}

// MARK: All public entry
extension JZLocationConverter {
    public func wgs84ToGcj02(_ wgs84Point:CLLocationCoordinate2D,result:@escaping (_ gcj02Point:CLLocationCoordinate2D) -> Void) {
        self.gcj02Encrypt(wgs84Point, result: result)
    }
    
    public func wgs84ToBd09(_ wgs84Point:CLLocationCoordinate2D,result:@escaping (_ bd09Point:CLLocationCoordinate2D) -> Void) {
        self.gcj02Encrypt(wgs84Point) { (gcj02Point:CLLocationCoordinate2D) in
            self.bd09Encrypt(gcj02Point, result: result);
        }
    }
    
    public func gcj02ToWgs84(_ gcj02Point:CLLocationCoordinate2D,result:@escaping (_ wgs84Point:CLLocationCoordinate2D) -> Void) {
        self.gcj02Decrypt(gcj02Point, result: result)
    }
    
    public func gcj02ToBd09(_ gcj02Point:CLLocationCoordinate2D,result:@escaping (_ bd09Point:CLLocationCoordinate2D) -> Void) {
        self.bd09Encrypt(gcj02Point, result: result);
    }
    
    public func bd09ToGcj02(_ bd09Point:CLLocationCoordinate2D,result:@escaping (_ gcj02Point:CLLocationCoordinate2D) -> Void) {
        self.bd09Decrypt(bd09Point, result: result)
    }
    
    public func bd09ToWgs84(_ bd09Point:CLLocationCoordinate2D,result:@escaping (_ wgs84Point:CLLocationCoordinate2D) -> Void) {
        self.bd09Decrypt(bd09Point) { (gcj02Point:CLLocationCoordinate2D) in
            self.gcj02Decrypt(gcj02Point, result: result);
        }
    }
   
    // MARK: Array conversion entry
    // BD-09 related conversion is comment out as it is not used and tested
   
   /**
    If coordinate inside area, will return GJC-02.
    If coordinate out of area, will return WGS-84.
    This matches the usage of MKMapView.
    */
    public func wgs84ToGcj02PointsAsync(_ wgs84Points:[CLLocationCoordinate2D], conversionType: JZConversionType, result:@escaping ([JZLocationResult]) -> Void) {
        let points = convertCoordinateToResult(type: .WGS84, coordinates: wgs84Points)
        self.gcj02EncryptPointsAsync(points, conversionType: conversionType, result: result)
    }
    
    public func wgs84ToGcj02Points(_ wgs84Points:[CLLocationCoordinate2D], conversionType: JZConversionType) -> [JZLocationResult] {
        let points = convertCoordinateToResult(type: .WGS84, coordinates: wgs84Points)
        return self.gcj02EncryptPoints(points, conversionType: conversionType)
    }
    
//    public func wgs84ToBd09Points(_ wgs84Points:[CLLocationCoordinate2D],result:@escaping ([JZLocationResult]) -> Void) {
//        let points = convertCoordinateToResult(type: .WGS84, coordinates: wgs84Points)
//        self.gcj02EncryptPoints(points) { (gcj02ResultPoints) in
//           // If the coordinate is outside area, gcj02EncryptPoints will return WGS-84 coordinate.
//           // This will make the conversion of bd09EncryptPoints incorrect.
//           self.bd09EncryptPoints(gcj02ResultPoints, result: result)
//        }
//    }
   
    /**
     If coordinate inside area, will return WGS-84.
     If coordinate out of area, will return GCJ-02.
     We should not obtain coordinate in GCJ-02 format if the coordinate is out of area.
    */
    public func gcj02ToWgs84PointsAsync(_ gcj02Points:[CLLocationCoordinate2D], conversionType: JZConversionType, result:@escaping ([JZLocationResult]) -> Void) {
        let points = convertCoordinateToResult(type: .GCJ02, coordinates: gcj02Points)
        self.gcj02DecryptPointsAsync(points, conversionType: conversionType, result: result)
    }
    
    public func gcj02ToWgs84Points(_ gcj02Points:[CLLocationCoordinate2D], conversionType: JZConversionType) -> [JZLocationResult] {
        let points = convertCoordinateToResult(type: .GCJ02, coordinates: gcj02Points)
        return self.gcj02DecryptPoints(points, conversionType: conversionType)
    }
    
//   public func gcj02ToBd09Points(_ gcj02Points:[CLLocationCoordinate2D],result:@escaping ([JZLocationResult]) -> Void) {
//      let points = convertCoordinateToResult(type: .GCJ02, coordinates: gcj02Points)
//      self.bd09EncryptPoints(points, result: result);
//    }
//
//   public func bd09ToGcj02Points(_ bd09Points:[CLLocationCoordinate2D],result:@escaping ([JZLocationResult]) -> Void) {
//      let points = convertCoordinateToResult(type: .BD09, coordinates: bd09Points)
//      self.bd09DecryptPoints(points, result: result)
//    }
//    
//    public func bd09ToWgs84Points(_ bd09Points:[CLLocationCoordinate2D],result:@escaping ([JZLocationResult]) -> Void) {
//        let points = convertCoordinateToResult(type: .BD09, coordinates: bd09Points)
//        // This conversion will not check is inside area and convert BD-09 to GCJ-02 directly.
//        self.bd09DecryptPoints(points) { bd09ResultPoints in
//            // If the coordinate is outside area, this will return GCJ-02 due to the reason above.
//            // Returning GCJ-02 is not expected.
//            // As there is no usage of BD-09 conversion, this function is comment out.
//            self.gcj02DecryptPoints(bd09ResultPoints, result: result)
//        }
//    }
   
   // MARK: Uncomment below entry if BD09 conversion completed, the above entry should marked as private
//   public func convertPoints(_ points: [CLLocationCoordinate2D], from: JZLocationType, to: JZLocationType, convertMode: JZConversionType) -> [JZLocationResult] {
//      guard from != to else { return convertCoordinateToResult(type: from, coordinates: points) }
//      
//      switch from {
//      case .WGS84:
//         switch to {
//         case .WGS84:
//            print("") // Not expected
//         case .GCJ02:
//            return wgs84ToGcj02Points(points, conversionType: convertMode)
//         case .BD09:
//            return wgs84ToBd09Points(points, conversionType: convertMode)
//         }
//      case .GCJ02:
//         switch to {
//         case .WGS84:
//            return gcj02ToWgs84Points(points, conversionType: convertMode)
//         case .GCJ02:
//            print("") // Not expected
//         case .BD09:
//            return gcj02ToBd09Points(points, conversionType: convertMode)
//         }
//      case .BD09:
//         switch to {
//         case .WGS84:
//            return bd09ToWgs84Points(points, conversionType: convertMode)
//         case .GCJ02:
//            return bd09ToGcj02Points(points, conversionType: convertMode)
//         case .BD09:
//            print("") // Not expected
//         }
//      }
//   }
   
//   public func convertPointsAsync(_ points: [CLLocationCoordinate2D], from: JZLocationType, to: JZLocationType, convertMode: JZConversionType, completion: @escaping ([JZLocationResult]) -> ()) {
//      guard from != to else { completion(convertCoordinateToResult(type: from, coordinates: points)) }
//      
//      switch from {
//      case .WGS84:
//         switch to {
//         case .WGS84:
//            print("") // Not expected
//         case .GCJ02:
//            return wgs84ToGcj02PointsAsync(points, conversionType: convertMode, result: completion)
//         case .BD09:
//            return wgs84ToBd09PointsAsync(points, conversionType: convertMode, result: completion)
//         }
//      case .GCJ02:
//         switch to {
//         case .WGS84:
//            return gcj02ToWgs84PointsAsync(points, conversionType: convertMode, result: completion)
//         case .GCJ02:
//            print("") // Not expected
//         case .BD09:
//            return gcj02ToBd09PointsAsync(points, conversionType: convertMode, result: completion)
//         }
//      case .BD09:
//         switch to {
//         case .WGS84:
//            return bd09ToWgs84PointsAsync(points, conversionType: convertMode, result: completion)
//         case .GCJ02:
//            return bd09ToGcj02PointsAsync(points, conversionType: convertMode, result: completion)
//         case .BD09:
//            print("") // Not expected
//         }
//      }
//   }
}

public struct JZLocationResult {
    public var type: JZLocationType
    public var coordinate: CLLocationCoordinate2D
    
    /// Optional, will be updated after conversion
    public var isOutOfArea: Bool? = nil
    public var latitude: Double { coordinate.latitude }
    public var longitude: Double { coordinate.longitude }
    
    mutating func setCoordinate(latitude: Double, longitude: Double) {
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public enum JZLocationType {
    case WGS84
    case GCJ02
    case BD09
}

public enum JZConversionType {
    case FORCE
    case AUTO
    
    var isForceConversion: Bool {
        self == .FORCE
    }
}

