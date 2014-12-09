package models.archive.zip

import org.specs2.mutable.Specification
import org.specs2.specification.Scope

class EndOfCentralDirectoryRecordSpec extends Specification {

  "EndOfCentralDirectoryRecord" should {

    "write values to stream in" in new CentralDirectoryContext {

      val expectedValues =
        writeInt(0x06054b50) ++
        writeShort(0) ++
        writeShort(0) ++
        writeShort(numberOfEntries) ++
        writeShort(numberOfEntries) ++
        writeInt(centralDirectorySize) ++
        writeInt(centralDirectoryOffset) ++
        writeShort(0)

      val output = endOfCentralDirectoryRecord.bytes

      output must be equalTo expectedValues

    }

    trait CentralDirectoryContext extends Scope with LittleEndianWriter {
      val numberOfEntries = 10

      val centralDirectorySize = 1023
      val centralDirectoryOffset = 42001

      val endOfCentralDirectoryRecord = new EndOfCentralDirectoryRecord(
        numberOfEntries,
        centralDirectorySize,
        centralDirectoryOffset
      )
    }
  }
}
