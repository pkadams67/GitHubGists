//
//  AlamofireRequest+JSONSerializable.swift
//  GitHubGists
//
//  Created by Paul Kirk Adams on 7/21/16.
//  Copyright © 2016 Paul Kirk Adams. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

extension Alamofire.Request {

    public func responseObject<T: ResponseJSONObjectSerializable>(completionHandler:
        Response<T, NSError> -> Void) -> Self {
        let serializer = ResponseSerializer<T, NSError> { request, response, data, error in
            guard error == nil else {
                return .Failure(error!)
            }
            guard let responseData = data else {
                let failureReason = "Object couldn't be serialized because input data was nil."
                let error = Error.errorWithCode(.DataSerializationFailed,
                    failureReason: failureReason)
                return .Failure(error)
            }
            let JSONResponseSerializer = Request.JSONResponseSerializer(options: .AllowFragments)
            let result = JSONResponseSerializer.serializeResponse(request, response,
                responseData, error)
            switch result {
            case .Failure(let error):
                return .Failure(error)
            case .Success(let value):
                let json = SwiftyJSON.JSON(value)
                if let errorMessage = json["message"].string {
                    let error = Error.errorWithCode(.DataSerializationFailed,
                        failureReason: errorMessage)
                    return .Failure(error)
                }
                guard let object = T(json: json) else {
                    let failureReason = "Object couldn't be created from JSON."
                    let error = Error.errorWithCode(.JSONSerializationFailed,
                        failureReason: failureReason)
                    return .Failure(error)
                }
                return .Success(object)
            }
        }
        return response(responseSerializer: serializer, completionHandler: completionHandler)
    }
    
    public func responseArray<T: ResponseJSONObjectSerializable>(
        completionHandler: Response<[T], NSError> -> Void) -> Self {
        let serializer = ResponseSerializer<[T], NSError> { request, response, data, error in
            guard error == nil else {
                return .Failure(error!)
            }
            guard let responseData = data else {
                let failureReason = "Array couldn't be serialized because input data was nil."
                let error = Error.errorWithCode(.DataSerializationFailed,
                    failureReason: failureReason)
                return .Failure(error)
            }
            let JSONResponseSerializer = Request.JSONResponseSerializer(options: .AllowFragments)
            let result = JSONResponseSerializer.serializeResponse(request, response,
                responseData, error)
            switch result {
            case .Failure(let error):
                return .Failure(error)
            case .Success(let value):
                let json = SwiftyJSON.JSON(value)
                if let errorMessage = json["message"].string {
                    let error = Error.errorWithCode(.DataSerializationFailed,
                        failureReason: errorMessage)
                    return .Failure(error)
                }
                var objects: [T] = []
                for (_, item) in json {
                    if let object = T(json: item) {
                        objects.append(object)
                    }
                }
                return .Success(objects)
            }
        }
        return response(responseSerializer: serializer, completionHandler: completionHandler)
    }
}