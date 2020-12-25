//
//  TestFiles.swift
//  ServerTests
//
//  Created by Christopher G Prince on 10/23/18.
//

import Foundation
import XCTest
import ServerShared

struct TestFile {
    enum FileContents {
        case string(String)
        case url(URL)
    }
    
    let dropboxCheckSum:String
    let contents: FileContents
    let mimeType: MimeType
    
    func checkSum(type: AccountScheme.AccountName) -> String! {
        switch type {
        case AccountScheme.dropbox.accountName:
            return dropboxCheckSum
            
        default:
            XCTFail()
            return nil
        }
    }
    
    static let test1 = TestFile(
        dropboxCheckSum: "42a873ac3abd02122d27e80486c6fa1ef78694e8505fcec9cbcc8a7728ba8949",
        contents: .string("Hello World"),
        mimeType: .text)
    
    static let test2 = TestFile(
        dropboxCheckSum: "3e1c5665be7f2f5552efb9fd93df8fe9d58c54619fefe1a5b474e38464391011",
        contents: .string("This is some longer text that I'm typing here and hopefullly I don't get too bored"),
        mimeType: .text)

#if os(macOS)
        private static let catFileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
#else
        private static let catFileURL = URL(fileURLWithPath: "./TestDataFiles/Cat.jpg")
#endif

    static let catJpg = TestFile(
        dropboxCheckSum: "d342f6ab222c322e5fccf148435ef32bd676d7ce0baa72ea88593ef93bef8ac2",
        contents: .url(catFileURL),
        mimeType: .jpeg)

#if os(macOS)
        private static let urlFile = URL(fileURLWithPath: "/tmp/example.url")
#else
        private static let urlFile = URL(fileURLWithPath: "./TestDataFiles/example.url")
#endif

    // The specific hash values are obtained from bootstraps in the iOS client test cases.
    static let testUrlFile = TestFile(
        dropboxCheckSum: "842520e78cc66fad4ea3c5f24ad11734075d97d686ca10b799e726950ad065e7",
        contents: .url(urlFile),
        mimeType: .url)
}
