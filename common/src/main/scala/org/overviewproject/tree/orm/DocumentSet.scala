package org.overviewproject.tree.orm

import java.sql.Timestamp
import org.squeryl.KeyedEntity
import org.squeryl.annotations.Column
import scala.language.implicitConversions

import org.overviewproject.models.{DocumentSet=>GoodDocumentSet}
import org.overviewproject.util.DocumentSetVersion

case class DocumentSet(
  override val id: Long = 0,
  title: String = "",
  query: Option[String] = None,
  @Column("public") isPublic: Boolean = false,
  createdAt: Timestamp = new Timestamp(scala.compat.Platform.currentTime),
  documentCount: Int = 0,
  documentProcessingErrorCount: Int = 0,
  importOverflowCount: Int = 0,
  uploadedFileId: Option[Long] = None,
  version: Int = DocumentSetVersion.current,
  deleted: Boolean = false) extends KeyedEntity[Long] {

  // https://www.assembla.com/spaces/squeryl/tickets/68-add-support-for-full-updates-on-immutable-case-classes#/followers/ticket:68
  override def isPersisted(): Boolean = (id > 0)

  def toDocumentSet: GoodDocumentSet = GoodDocumentSet(
    id,
    title,
    query,
    isPublic,
    createdAt,
    documentCount,
    documentProcessingErrorCount,
    importOverflowCount,
    uploadedFileId,
    version,
    deleted
  )
}

object DocumentSet {
  implicit def toLong(documentSet: DocumentSet) = documentSet.id
}
