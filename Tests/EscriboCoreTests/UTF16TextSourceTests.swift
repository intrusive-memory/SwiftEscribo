import Testing

@testable import EscriboCore

/// A text source backed by nothing but an array of code units.
///
/// Its job is to prove the abstraction is not `String`-shaped. `NSTextStorage` conforms
/// in `SwiftEscribo` (Sortie 9) and is `NSString`-backed; if anything in `EscriboCore`
/// quietly assumed a Swift `String` underneath, it would compile today and fail there.
private struct CodeUnitSource: UTF16TextSource {
  let units: [UInt16]

  init(_ text: String) { self.units = Array(text.utf16) }

  var utf16Count: Int { units.count }

  func copyUTF16CodeUnits(in range: Range<Int>, into buffer: UnsafeMutableBufferPointer<UInt16>) {
    var out = 0
    for offset in range {
      buffer[out] = units[offset]
      out += 1
    }
  }
}

@Suite("UTF-16 text access")
struct UTF16TextSourceTests {

  @Test("A String reports its length in code units, not characters")
  func stringLengthIsCodeUnits() {
    // The one measurement everything downstream is expressed in. An emoji is two code
    // units and one character, and a length that counted characters would make every
    // range after it short by one — silently, because both numbers look plausible.
    #expect("".utf16Count == 0)
    #expect("abc".utf16Count == 3)
    #expect("a\u{1F600}b".utf16Count == 4)
    #expect("a\r\nb".utf16Count == 4)
  }

  @Test("Reading a range yields exactly that range's code units")
  func readingARange() {
    let text = "alpha\r\nbravo"
    var buffer = UTF16LineBuffer()
    let expected = Array(text.utf16)

    for lower in 0...text.utf16Count {
      for upper in lower...text.utf16Count {
        let read = buffer.withCodeUnits(of: lower..<upper, in: text) { Array($0) }
        #expect(read == Array(expected[lower..<upper]))
      }
    }
  }

  @Test("The staging buffer is reused without leaking stale code units")
  func bufferReuseDoesNotLeak() {
    // The buffer grows to the largest line ever read and is then reused, which is the
    // whole reason it exists — one allocation per scan instead of one per line. The
    // hazard that comes with it is a short read seeing the tail of a long one, so the
    // yielded buffer is right-sized rather than the raw scratch. A leak here would show
    // up as a scanner finding a terminator that is not in the line.
    var buffer = UTF16LineBuffer()
    let long = String(repeating: "z", count: 8000) + "\n"
    let readLong = buffer.withCodeUnits(of: 0..<long.utf16Count, in: long) { Array($0) }
    #expect(readLong.count == 8001)

    let short = "ab"
    let readShort = buffer.withCodeUnits(of: 0..<2, in: short) { Array($0) }
    #expect(readShort == Array("ab".utf16))
    #expect(readShort.count == 2)

    let empty = buffer.withCodeUnits(of: 0..<0, in: short) { Array($0) }
    #expect(empty.isEmpty)
  }

  @Test("Reads are whole runs, so the per-line cost is one dispatch")
  func readsAreBulk() {
    // REQUIREMENTS.md § Edits and text access: the scanner reads a line at a time, not a
    // code unit at a time, so dispatch is per line rather than per character. This
    // counts the calls to prove the protocol is actually being used that way — a
    // per-code-unit read shape would still pass every correctness test in this file
    // while costing a million dispatches on a one-megabyte line.
    final class CountingSource: UTF16TextSource {
      let units: [UInt16]
      var readCount = 0
      init(_ text: String) { self.units = Array(text.utf16) }
      var utf16Count: Int { units.count }
      func copyUTF16CodeUnits(
        in range: Range<Int>,
        into buffer: UnsafeMutableBufferPointer<UInt16>
      ) {
        readCount += 1
        var out = 0
        for offset in range {
          buffer[out] = units[offset]
          out += 1
        }
      }
    }

    // 10 000 code units on one line: three 4 096-unit chunk reads, not 10 000.
    let source = CountingSource(String(repeating: "a", count: 10_000))
    let index = LineIndex(source)
    #expect(index.lineCount == 1)
    #expect(index.line(at: 0).range == 0..<10_000)
    #expect(source.readCount == 3)
  }

  @Test("A non-String source indexes identically to the same text as a String")
  func nonStringSourceIndexesIdentically() {
    for fixture in terminatorFixtures {
      #expect(LineIndex(CodeUnitSource(fixture.text)) == LineIndex(fixture.text))
    }
  }
}
