package persistence

import org.overviewproject.test.DbSpecification
import org.overviewproject.test.DbSetup._

class UploadedFileLoaderSpec extends DbSpecification {

  step(setupDb)
  
  "UploadedFileLoader" should {
    
    "load uploaded file values" in new DbTestContext {
      val oid = 100l
      val size = 1999l
      val contentType =  "application/octet-stream"
        
      val uploadedFileId = insertUploadedFile(oid, "content-disposition", contentType, size)
      
      val uploadedFile = EncodedUploadFile.load(uploadedFileId) 
      uploadedFile.contentsOid must be equalTo oid
      uploadedFile.contentType must be equalTo contentType
      uploadedFile.size must be equalTo size
    }
  }
  
  step(shutdownDb)
  
  case class TestUploadFile(contentType: String) extends EncodedUploadFile {
    val contentsOid: Long = 0l
    val size: Long = 100
  }
  
  "UploadedFile" should {
    
    "return None if no encoding can be found" in {
      val uploadedFile = TestUploadFile("application/octet-stream")
      uploadedFile.encoding must beNone
    }
    
    "return specified encoding" in {
      val encoding = "someEncoding"
      val uploadedFile = TestUploadFile("application/octet-stream; charset=" + encoding)
      uploadedFile.encoding must beSome.like { case c => c must be equalTo(encoding) }
    }
  }
}