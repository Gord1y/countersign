import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ReplyWriterTests {
  @Test func anOpenPipeReceivesTheBytesAndANewline() throws {
    let pipe = Pipe()
    let written = ReplyWriter.write(Data("{}".utf8), to: pipe.fileHandleForWriting)
    try pipe.fileHandleForWriting.close()
    let received = try pipe.fileHandleForReading.readToEnd()
    #expect(written)
    #expect(received == Data("{}\n".utf8))
  }

  @Test func aPipeWhoseReaderIsGoneReturnsFalseWithoutCrashing() throws {
    signal(SIGPIPE, SIG_IGN)
    let pipe = Pipe()
    try pipe.fileHandleForReading.close()
    #expect(!ReplyWriter.write(Data("{}".utf8), to: pipe.fileHandleForWriting))
  }
}
