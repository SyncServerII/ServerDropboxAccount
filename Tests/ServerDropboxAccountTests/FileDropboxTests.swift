//
//  DropboxTests.swift
//  Server
//
//  Created by Christopher Prince on 12/10/17.
//
//

import XCTest
import Foundation
import LoggerAPI
import HeliumLogger
import ServerShared
@testable import ServerDropboxAccount
import ServerAccount

struct DropboxPlist: Decodable, DropboxCredsConfiguration {
    let token: String // access token
    let id: String
    let refreshToken: String?

    var DropboxAppKey:String?
    var DropboxAppSecret:String?
    
    static func load(from url: URL) -> Self {
        guard let data = try? Data(contentsOf: url) else {
            fatalError("Could not get data from url")
        }

        let decoder = PropertyListDecoder()

        guard let plist = try? decoder.decode(Self.self, from: data) else {
            fatalError("Could not decode the plist")
        }

        return plist
    }
}

class FileDropboxTests: XCTestCase {
    // In my Dropbox:
    let knownPresentFile = "DO-NOT-REMOVE.txt"
    let knownPresentFile2 = "DO-NOT-REMOVE2.txt"

    let knownAbsentFile = "Markwa.Farkwa.Blarkwa"
    var plist:DropboxPlist!
    var plistRevoked:DropboxPlist!

    override func setUp() {
        super.setUp()
        // See https://stackoverflow.com/questions/47177036
        // I know this is gross. Swift packages just don't have a good way to access resources right now.
        plist = DropboxPlist.load(from: URL(fileURLWithPath: "../Private/ServerDropboxAccount/token.plist"))
        plistRevoked = DropboxPlist.load(from: URL(fileURLWithPath: "../Private/ServerDropboxAccount/tokenRevoked.plist"))
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
#if false
    func testBoostrapKnownFile() {
        guard let creds = DropboxCreds() else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        let contents = "hello, world"
    
        guard let fileContentsData = contents.data(using: .ascii) else {
            XCTFail()
            return
        }

        let cloudFileName = knownPresentFile
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.uploadFile(cloudFileName: cloudFileName, data: fileContentsData) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("\(error)")
            case .accessTokenRevokedOrExpired:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
#endif

    func testCheckForFileFailsWithFileThatDoesNotExist() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: "foobar") { result in
            switch result {
            case .success(let found):
                XCTAssert(!found)
            case .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                XCTFail()
            }

            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    func testCheckForFileWorksWithExistingFile() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: knownPresentFile) { result in
            switch result {
            case .success(let found):
                XCTAssert(found)
            case .failure, .accessTokenRevokedOrExpired:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }

    func uploadFile(file: TestFile, mimeType: MimeType) {
        let fileName = Foundation.UUID().uuidString
        
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        let fileContentsData: Data!

        switch file.contents {
        case .string(let fileContents):
            fileContentsData = fileContents.data(using: .ascii)!
        case .url(let url):
            fileContentsData = try? Data(contentsOf: url)
        }
        
        guard fileContentsData != nil else {
            XCTFail()
            return
        }
        
        creds.uploadFile(withName: fileName, data: fileContentsData) { result in
            switch result {
            case .success(let hash):
                XCTAssert(hash == file.dropboxCheckSum)
            case .failure(let error):
                Log.error("uploadFile: \(error)")
                XCTFail()
            case .accessTokenRevokedOrExpired:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testUploadFileWorks() {
        uploadFile(file: .test1, mimeType: .text)
    }
    
    func testUploadURLFileWorks() {
        uploadFile(file: .testUrlFile, mimeType: .url)
    }
    
    func testUploadWithRevokedToken() {
        let fileName = Foundation.UUID().uuidString
        
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plistRevoked.token
        creds.accountId = plistRevoked.id
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        let stringFile = TestFile.test1
        
        guard case .string(let stringContents) = stringFile.contents else {
            XCTFail()
            return
        }
        
        let fileContentsData = stringContents.data(using: .ascii)!
        
        creds.uploadFile(withName: fileName, data: fileContentsData) { result in
            switch result {
            case .success:
                XCTFail()
            case .failure(let error):
                Log.error("uploadFile: \(error)")
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    @discardableResult
    func uploadFile(accountType: AccountScheme.AccountName, creds: CloudStorage, deviceUUID:String, testFile: TestFile, uploadRequest:UploadFileRequest, fileVersion: FileVersionInt, options:CloudStorageFileNameOptions? = nil, nonStandardFileName: String? = nil, failureExpected: Bool = false, errorExpected: CloudStorageError? = nil, expectAccessTokenRevokedOrExpired: Bool = false) -> String? {
    
        var fileContentsData: Data!
        
        switch testFile.contents {
        case .string(let fileContents):
            fileContentsData = fileContents.data(using: .ascii)!
        case .url(let url):
            fileContentsData = try? Data(contentsOf: url)
        }
        
        guard fileContentsData != nil else {
            XCTFail()
            return nil
        }
        
        guard let mimeType = uploadRequest.mimeType else {
            XCTFail()
            return nil
        }
        
        var cloudFileName:String!
        if let nonStandardFileName = nonStandardFileName {
            cloudFileName = nonStandardFileName
        }
        else {
            cloudFileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, mimeType: mimeType, fileVersion: fileVersion)
        }
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.uploadFile(cloudFileName: cloudFileName, data: fileContentsData, options: options) { result in
            switch result {
            case .success(let checkSum):
                XCTAssert(testFile.checkSum(type: accountType) == checkSum)
                Log.debug("checkSum: \(checkSum)")
                if failureExpected {
                    XCTFail()
                }
            case .failure(let error):
                if expectAccessTokenRevokedOrExpired {
                    XCTFail()
                }
                
                cloudFileName = nil
                Log.debug("uploadFile: \(error)")
                if !failureExpected {
                    XCTFail()
                }
                
                if let errorExpected = errorExpected {
                    guard let error = error as? CloudStorageError else {
                        XCTFail()
                        exp.fulfill()
                        return
                    }
                    
                    XCTAssert(error == errorExpected)
                }
            case .accessTokenRevokedOrExpired:
                if !expectAccessTokenRevokedOrExpired {
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return cloudFileName
    }

    func fullUpload(file: TestFile, mimeType: MimeType) {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = mimeType.rawValue
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.dropboxCheckSum
        
        uploadFile(accountType: AccountScheme.dropbox.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest, fileVersion: 0)
        
        // The second time we try it, it should fail with CloudStorageError.alreadyUploaded -- same file.
        uploadFile(accountType: AccountScheme.dropbox.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest, fileVersion: 0, failureExpected: true, errorExpected: CloudStorageError.alreadyUploaded)
    }
    
    func testFullUploadWorks() {
        fullUpload(file: .test1, mimeType: .text)
    }

    func testFullUploadURLWorks() {
        fullUpload(file: .testUrlFile, mimeType: .url)
    }
    
    func downloadFile(creds: DropboxCreds, cloudFileName: String, expectedStringFile:TestFile? = nil, expectedFailure: Bool = false, expectedFileNotFound: Bool = false, expectedRevokedToken: Bool = false) {
        let exp = expectation(description: "\(#function)\(#line)")

        creds.downloadFile(cloudFileName: cloudFileName) { result in
            switch result {
            case .success(let data, let checkSum):
                if let expectedStringFile = expectedStringFile {
                    guard case .string(let expectedContents) = expectedStringFile.contents else {
                        XCTFail()
                        return
                    }
                    
                    guard let str = String(data: data, encoding: String.Encoding.ascii) else {
                        XCTFail()
                        Log.error("Failed on string decoding")
                        return
                    }
                    
                    XCTAssert(checkSum == expectedStringFile.dropboxCheckSum)
                    XCTAssert(str == expectedContents)
                }
                
                if expectedFailure || expectedRevokedToken || expectedFileNotFound {
                    XCTFail()
                }
            case .failure(let error):
                if !expectedFailure || expectedRevokedToken || expectedFileNotFound {
                    XCTFail()
                    Log.error("Failed download: \(error)")
                }
            case .accessTokenRevokedOrExpired:
                if !expectedRevokedToken || expectedFileNotFound || expectedFailure {
                    XCTFail()
                }
            case .fileNotFound:
                if !expectedFileNotFound || expectedRevokedToken || expectedFailure{
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDownloadOfNonExistingFileFails() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        downloadFile(creds: creds, cloudFileName: knownAbsentFile, expectedFileNotFound: true)
    }
    
    func testSimpleDownloadWorks() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        downloadFile(creds: creds, cloudFileName: knownPresentFile)
    }

    func testDownloadWithRevokedToken() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plistRevoked.token
        creds.accountId = plistRevoked.id
        
        downloadFile(creds: creds, cloudFileName: knownPresentFile, expectedRevokedToken: true)
    }

    func testSimpleDownloadWorks2() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        downloadFile(creds: creds, cloudFileName: knownPresentFile2)
    }

    func testUploadAndDownloadWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id

        let file = TestFile.test1
        guard case .string = file.contents else {
            XCTFail()
            return
        }
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.dropboxCheckSum

        let fileVersion: FileVersionInt = 0
        
        uploadFile(accountType: AccountScheme.dropbox.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest, fileVersion: fileVersion)
        
        guard let mimeType = uploadRequest.mimeType else {
            XCTFail()
            return
        }
        
        let cloudFileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: mimeType, fileVersion: fileVersion)
        Log.debug("cloudFileName: \(cloudFileName)")
        downloadFile(creds: creds, cloudFileName: cloudFileName, expectedStringFile: file)
    }

    func deleteFile(creds: DropboxCreds, cloudFileName: String, expectedFailure: Bool = false) {
        let exp = expectation(description: "\(#function)\(#line)")

        creds.deleteFile(cloudFileName: cloudFileName) { result in
            switch result {
            case .success:
                if expectedFailure {
                    XCTFail()
                }
            case .accessTokenRevokedOrExpired:
                XCTFail()
            case .failure(let error):
                if !expectedFailure {
                    XCTFail()
                    Log.error("Failed download: \(error)")
                }
            }

            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }

    func testDeletionWithRevokedAccessToken() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plistRevoked.token
        creds.accountId = plistRevoked.id
        
        let existingFile = knownPresentFile
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.deleteFile(cloudFileName: existingFile) { result in
            switch result {
            case .success:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            case .failure:
                XCTFail()
            }

            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        let result = lookupFile(cloudFileName: existingFile)
        XCTAssert(result == true)
    }

    func testDeletionOfNonExistingFileFails() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        deleteFile(creds: creds, cloudFileName: knownAbsentFile, expectedFailure: true)
    }
    
    func deletionOfExistingFile(file: TestFile, mimeType: MimeType) {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = mimeType.rawValue
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.dropboxCheckSum
        
        guard let fileName = uploadFile(accountType: AccountScheme.dropbox.accountName, creds: creds, deviceUUID:deviceUUID, testFile:file, uploadRequest:uploadRequest, fileVersion: 0) else {
            XCTFail()
            return
        }
        
        deleteFile(creds: creds, cloudFileName: fileName)
    }
    
    func testDeletionOfExistingFileWorks() {
        deletionOfExistingFile(file: .test1, mimeType: .text)
    }

    func testDeletionOfExistingURLFileWorks() {
        deletionOfExistingFile(file: .testUrlFile, mimeType: .url)
    }

    func lookupFile(cloudFileName: String, expectError:Bool = false) -> Bool? {
        var foundResult: Bool?
        
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return nil
        }
        
        creds.accessToken = plist.token
        creds.accountId = plist.id
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.lookupFile(cloudFileName:cloudFileName) { result in
            switch result {
            case .success(let found):
                if expectError {
                    XCTFail()
                }
                else {
                   foundResult = found
                }
            case .failure, .accessTokenRevokedOrExpired:
                if !expectError {
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return foundResult
    }
    
    func testLookupFileThatExists() {
        let result = lookupFile(cloudFileName: knownPresentFile)
        XCTAssert(result == true)
    }
    
    func testLookupFileThatDoesNotExist() {
        let result = lookupFile(cloudFileName: knownAbsentFile)
        XCTAssert(result == false)
    }

    func testLookupWithRevokedAccessToken() {
        guard let creds = DropboxCreds(configuration: nil, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accessToken = plistRevoked.token
        creds.accountId = plistRevoked.id
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.lookupFile(cloudFileName:knownPresentFile) { result in
            switch result {
            case .success, .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
}

extension FileDropboxTests {
    static var allTests : [(String, (FileDropboxTests) -> () throws -> Void)] {
        return [
            /*
            ("testCheckForFileFailsWithFileThatDoesNotExist", testCheckForFileFailsWithFileThatDoesNotExist),
            ("testCheckForFileWorksWithExistingFile", testCheckForFileWorksWithExistingFile),
            ("testUploadFileWorks", testUploadFileWorks),
            ("testUploadURLFileWorks", testUploadURLFileWorks),
            ("testUploadWithRevokedToken", testUploadWithRevokedToken),
            ("testFullUploadWorks", testFullUploadWorks),
            ("testFullUploadURLWorks", testFullUploadURLWorks),
            ("testDownloadOfNonExistingFileFails", testDownloadOfNonExistingFileFails),
            ("testSimpleDownloadWorks", testSimpleDownloadWorks),
            ("testDownloadWithRevokedToken", testDownloadWithRevokedToken),
            ("testSimpleDownloadWorks2", testSimpleDownloadWorks2),
            ("testUploadAndDownloadWorks", testUploadAndDownloadWorks),
            ("testDeletionWithRevokedAccessToken", testDeletionWithRevokedAccessToken),
            ("testDeletionOfNonExistingFileFails", testDeletionOfNonExistingFileFails),
            ("testDeletionOfExistingFileWorks", testDeletionOfExistingFileWorks),
            ("testDeletionOfExistingURLFileWorks", testDeletionOfExistingURLFileWorks),
            ("testLookupFileThatDoesNotExist", testLookupFileThatDoesNotExist),
            ("testLookupFileThatExists", testLookupFileThatExists),
            ("testLookupWithRevokedAccessToken", testLookupWithRevokedAccessToken)
            */
        ]
    }
}

