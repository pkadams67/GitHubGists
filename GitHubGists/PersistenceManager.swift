//
//  PersistenceManager.swift
//  GitHubGists
//
//  Created by Paul Kirk Adams on 7/21/16.
//  Copyright © 2016 Paul Kirk Adams. All rights reserved.
//

import Foundation

enum Path: String {
    case Public = "Public"
    case Starred = "Starred"
    case MyGists = "MyGists"
}

class PersistenceManager {

    class private func documentsDirectory() -> NSString {
        let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
        let documentDirectory = paths[0] as NSString
        return documentDirectory
    }
    
    class func saveArray<T: NSCoding>(arrayToSave: [T], path: Path) -> Bool {
        let file = documentsDirectory().stringByAppendingPathComponent(path.rawValue)
        return NSKeyedArchiver.archiveRootObject(arrayToSave, toFile: file)
    }
    
    class func loadArray<T: NSCoding>(path: Path) -> [T]? {
        let file = documentsDirectory().stringByAppendingPathComponent(path.rawValue)
        let result = NSKeyedUnarchiver.unarchiveObjectWithFile(file)
        return result as? [T]
    }
}