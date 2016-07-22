//
//  File.swift
//  GitHubGists
//
//  Created by Paul Kirk Adams on 7/21/16.
//  Copyright © 2016 Paul Kirk Adams. All rights reserved.
//

import Foundation
import SwiftyJSON

class File: NSObject, NSCoding, ResponseJSONObjectSerializable {
    
    var filename: String?
    var raw_url: String?
    var content: String?
    
    required init?(json: JSON) {
        self.filename = json["filename"].string
        self.raw_url = json["raw_url"].string
    }
    
    init?(aName: String?, aContent: String?) {
        self.filename = aName
        self.content = aContent
    }
    
    @objc func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(self.filename, forKey: "filename")
        aCoder.encodeObject(self.raw_url, forKey: "raw_url")
        aCoder.encodeObject(self.content, forKey: "content")
    }
    
    @objc required convenience init?(coder aDecoder: NSCoder) {
        let filename = aDecoder.decodeObjectForKey("filename") as? String
        let content = aDecoder.decodeObjectForKey("content") as? String
        self.init(aName: filename, aContent: content)
        self.raw_url = aDecoder.decodeObjectForKey("raw_url") as? String
    }
}