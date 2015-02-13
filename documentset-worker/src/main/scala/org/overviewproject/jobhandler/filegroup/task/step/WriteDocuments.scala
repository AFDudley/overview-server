package org.overviewproject.jobhandler.filegroup.task.step

import org.overviewproject.util.BulkDocumentWriter
import scala.concurrent.ExecutionContext.Implicits.global
import scala.concurrent.Future
import org.overviewproject.models.Document

trait WriteDocuments extends TaskStep {
  
  protected val storage: Storage
  protected val bulkDocumentWriter: BulkDocumentWriter
  protected val documents: Seq[Document]
  
  override def execute: Future[TaskStep] = for { 
    docsAdded <- Future.sequence(documents.map(bulkDocumentWriter.addAndFlushIfNeeded))
    batchFlushed <- bulkDocumentWriter.flush
    deleted <- storage.deleteTempDocumentSetFiles(documents)
  } yield FinalStep

  
  protected trait Storage {
    def deleteTempDocumentSetFiles(documents: Seq[Document]): Future[Int]
  }
}