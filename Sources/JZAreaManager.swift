//
//  JZAreaManager.swift
//  JZLocationConverterDemo
//
//  Created by jack zhou on 23/08/2017.
//  Copyright © 2017 Jack. All rights reserved.
//
import Foundation
import CoreLocation

public enum JZFileError: Error {
    case FileNotFound
    case EmptyData
    case invalidData
}
open class JZAreaManager {
   
   private(set) var points:Array<Array<Double>>?
   
   // By changing this value, will skip the checking of point inside area. This can reduce the time for converting continueous location
   // The greater the value, the fewer checking of point inside area, the faster the conversion of numerous location
   public static var CheckingFrequencyOfBoundary = 0
   
   fileprivate let queue = DispatchQueue(label: "JZ.LocationConverter.AreaManager")
   
   public static let `default`: JZAreaManager = {
      return JZAreaManager()
   }()
   
   public static func start(filePath:String? = Bundle.main.path(forResource: "GCJ02", ofType: "json"),
                            finished:((_ error:JZFileError?) -> Void)?) {
      guard let filePath = filePath else {
         DispatchQueue.main.async {
            if finished != nil {
               finished!(JZFileError.FileNotFound)
            }
         }
         return
      }
      JZAreaManager.default.queue.async {
         guard let jsonString = try? String(contentsOfFile: filePath) else {
            DispatchQueue.main.async {
               if finished != nil {
                  finished!(JZFileError.EmptyData)
               }
            }
            return
         }
         guard let data = jsonString.data(using: .utf8) else {
            DispatchQueue.main.async {
               if finished != nil {
                  finished!(JZFileError.invalidData)
               }
            }
            return
         }
         guard let array = try? JSONSerialization.jsonObject(with: data, options: []) else {
            DispatchQueue.main.async {
               if finished != nil {
                  finished!(JZFileError.invalidData)
               }
            }
            return
         }
         JZAreaManager.default.points = array as? Array<Array<Double>>
         DispatchQueue.main.async {
            if finished != nil {
               finished!(nil)
            }
         }
      }
   }
   
   // This function use "Ray casting algorithm" to check whether the point lie inside or outside the area
   public func isOutOfArea(gcj02Point:CLLocationCoordinate2D,result:@escaping ((_ result:Bool)->Void)) -> Void {
      self.queue.async {
         var flag = false
         if JZAreaManager.default.points != nil {
            let length = (JZAreaManager.default.points?.count)!
            for idx in 0 ..< length {
               let nextIdx = (idx + 1) == length ? 0 : idx + 1
               let edgePoint = JZAreaManager.default.points![idx]
               let nextPoint = JZAreaManager.default.points![nextIdx]
               
               let pointX = edgePoint[1]
               let pointY = edgePoint[0]
               
               let nextPointX = nextPoint[1]
               let nextPointY = nextPoint[0]
               
               if (gcj02Point.longitude == pointX && gcj02Point.latitude == pointY) ||
                     (gcj02Point.longitude == nextPointX && gcj02Point.latitude == nextPointY)  {
                  flag = true
               }
               if((nextPointY < gcj02Point.latitude && pointY >= gcj02Point.latitude) ||
                  (nextPointY >= gcj02Point.latitude && pointY < gcj02Point.latitude)) {
                  let thX = nextPointX + (gcj02Point.latitude - nextPointY) * (pointX - nextPointX) / (pointY - nextPointY)
                  if(thX == gcj02Point.longitude) {
                     flag = true
                     break
                  }
                  if(thX > gcj02Point.longitude) {
                     flag = !flag
                  }
               }
            }
         }
         DispatchQueue.main.async {
            result(!flag)
         }
      }
   }
   
   public func isPointsOutOfArea(gcj02Locations:[JZLocationResult]) -> [JZLocationResult] {
      return convert(gcj02Locations: gcj02Locations)
   }
   
   public func isPointsOutOfAreaAsync(gcj02Locations:[JZLocationResult],result:@escaping ([JZLocationResult])->Void) {
      self.queue.async { [weak self] in
         if let locations = self?.convert(gcj02Locations: gcj02Locations) {
            DispatchQueue.main.async {
               result(locations)
            }
         } else {
            DispatchQueue.main.async {
               result(gcj02Locations)
            }
         }
      }
   }
   
   // This function use "Ray casting algorithm" to check whether the point lie inside or outside the area
   private func convert(gcj02Locations: [JZLocationResult]) -> [JZLocationResult] {
      guard let points = JZAreaManager.default.points else { return gcj02Locations }
      
      var resultArray: [JZLocationResult] = []
      var flag = false
      for (index, _gcj02Location) in gcj02Locations.enumerated() {
         
         // YY: Already check isInsideArea if not nil
         if _gcj02Location.isOutOfArea != nil {
            resultArray.append(_gcj02Location)
            continue
         }
         
         var gcj02Location = _gcj02Location
         
         // YY: Skip the checking to reduce checking time
         if JZAreaManager.CheckingFrequencyOfBoundary > 0, index % JZAreaManager.CheckingFrequencyOfBoundary > 0 {
            gcj02Location.isOutOfArea = !flag
            resultArray.append(gcj02Location)
            continue
         }
         
         flag = false
         for idx in 0 ..< points.count {
            let nextIdx = (idx + 1) == points.count ? 0 : idx + 1
            let edgePoint = JZAreaManager.default.points![idx]
            let nextPoint = JZAreaManager.default.points![nextIdx]
            
            let pointX = edgePoint[1]
            let pointY = edgePoint[0]
            
            let nextPointX = nextPoint[1]
            let nextPointY = nextPoint[0]
            
            if (gcj02Location.longitude == pointX && gcj02Location.latitude == pointY) || (gcj02Location.longitude == nextPointX && gcj02Location.latitude == nextPointY) {
               flag = true
            }
            
            if((nextPointY < gcj02Location.latitude && pointY >= gcj02Location.latitude) || (nextPointY >= gcj02Location.latitude && pointY < gcj02Location.latitude)) {
               let thX = nextPointX + (gcj02Location.latitude - nextPointY) * (pointX - nextPointX) / (pointY - nextPointY)
               if(thX == gcj02Location.longitude) {
                  flag = true
                  break
               }
               
               if(thX > gcj02Location.longitude) {
                  flag = !flag
               }
            }
         }
         gcj02Location.isOutOfArea = !flag
         resultArray.append(gcj02Location)
      }
      return resultArray
   }
}
