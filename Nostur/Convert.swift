////
////  Convert.swift
////  iotex-antenna-swift
////
////  Created by ququzone on 2019/8/10.
////  Copyright © 2019 IoTeX. All rights reserved.
////
//
//import Foundation
//import BigInt
//
//public class Convert {
//    public enum Unit: Int {
//        case Rau = 0
//        case KRau = 3
//        case MRau = 6
//        case GRau = 9
//        case Qev = 12
//        case Jing = 15
//        case Iotx = 18
//
//        public var decimals: Int {
//            return rawValue
//        }
//    }
//
//    public static func fromRau(number: String, unit: Unit) -> String {
//        guard let numberValue =  BigUInt(number.removeDecimal()) else {
//            return "0"
//        }
//        return fromRau(number: numberValue, unit: unit)
//    }
//
//    public static func fromRau(number: BigUInt, unit: Unit) -> String {
//        return formatToPrecision(number, numberDecimals: unit.decimals)!
//    }
//
//    public static func toRau(number: String, unit: Unit) -> String {
//        return String(parseToBigUInt(number, decimals: unit.decimals)!)
//    }
//
//    public static func parseToBigUInt(_ amount: String, decimals: Int = 18) -> BigUInt? {
//        let separators = CharacterSet(charactersIn: ".,")
//        let components = amount.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: separators)
//        guard components.count == 1 || components.count == 2 else {return nil}
//        let unitDecimals = decimals
//        guard let beforeDecPoint = BigUInt(components[0], radix: 10) else {return nil}
//        var mainPart = beforeDecPoint*BigUInt(10).power(unitDecimals)
//        if (components.count == 2) {
//            let numDigits = components[1].count
//            guard numDigits <= unitDecimals else {return nil}
//            guard let afterDecPoint = BigUInt(components[1], radix: 10) else {return nil}
//            let extraPart = afterDecPoint*BigUInt(10).power(unitDecimals-numDigits)
//            mainPart = mainPart + extraPart
//        }
//        return mainPart
//    }
//
//    public static func formatToPrecision(_ bigNumber: BigUInt, numberDecimals: Int = 18, formattingDecimals: Int = 18, decimalSeparator: String = ".", fallbackToScientific: Bool = false) -> String? {
//        if bigNumber == 0 {
//            return "0"
//        }
//        let unitDecimals = numberDecimals
//        var toDecimals = formattingDecimals
//        if unitDecimals < toDecimals {
//            toDecimals = unitDecimals
//        }
//        let divisor = BigUInt(10).power(unitDecimals)
//        let (quotient, remainder) = bigNumber.quotientAndRemainder(dividingBy: divisor)
//        var fullRemainder = String(remainder);
//        let fullPaddedRemainder = fullRemainder.paddingLeft(toLength: unitDecimals, withPad: "0")
//        var remainderPadded = fullPaddedRemainder[0..<toDecimals]
//        if remainderPadded == String(repeating: "0", count: toDecimals) {
//            if quotient != 0 {
//                return String(quotient)
//            } else if fallbackToScientific {
//                var firstDigit = 0
//                for char in fullPaddedRemainder {
//                    if (char == "0") {
//                        firstDigit = firstDigit + 1;
//                    } else {
//                        let firstDecimalUnit = String(fullPaddedRemainder[firstDigit ..< firstDigit+1])
//                        var remainingDigits = ""
//                        let numOfRemainingDecimals = fullPaddedRemainder.count - firstDigit - 1
//                        if numOfRemainingDecimals <= 0 {
//                            remainingDigits = ""
//                        } else if numOfRemainingDecimals > formattingDecimals {
//                            let end = firstDigit+1+formattingDecimals > fullPaddedRemainder.count ? fullPaddedRemainder.count : firstDigit+1+formattingDecimals
//                            remainingDigits = String(fullPaddedRemainder[firstDigit+1 ..< end])
//                        } else {
//                            remainingDigits = String(fullPaddedRemainder[firstDigit+1 ..< fullPaddedRemainder.count])
//                        }
//                        if remainingDigits != "" {
//                            fullRemainder = firstDecimalUnit + decimalSeparator + remainingDigits
//                        } else {
//                            fullRemainder = firstDecimalUnit
//                        }
//                        firstDigit = firstDigit + 1;
//                        break
//                    }
//                }
//                return fullRemainder + "e-" + String(firstDigit)
//            }
//        }
//        if (toDecimals == 0) {
//            return String(quotient)
//        }
//
//        let regex = try? NSRegularExpression(pattern: "0*$")
//        let range = NSMakeRange(0, remainderPadded.count)
//        remainderPadded = regex!.stringByReplacingMatches(in: remainderPadded, options: [], range: range, withTemplate: "")
//
//        return String(quotient) + decimalSeparator + remainderPadded
//    }
//}
