package models

import anorm._
import anorm.SqlParser._
import java.sql.Connection
import models.DatabaseStructure.{ DocumentListData, TagData }

class PersistentTagLoader extends DocumentTagDataLoader {

  def countDocuments(id: Long)(implicit c: Connection): Long = {
    SQL("SELECT COUNT(*) from document_tag WHERE tag_id = {tagId}").
      on("tagId" -> id).as(scalar[Long] single)
  }

  def countsPerNode(nodeIds: Seq[Long], id: Long)(implicit c: Connection): Seq[(Long, Long)] = {
    val nodeWhere = nodeIds match {
      case Nil => ""
      case _ => " AND node_document.node_id in " + nodeIds.mkString("(", ",", ")")
    }

    val nodeCounts = SQL("""
        SELECT node_id, COUNT(*) FROM node_document
        INNER JOIN document_tag ON node_document.document_id = document_tag.document_id
        WHERE document_tag.tag_id = {tagId}
        """ + nodeWhere +
      """
        GROUP BY node_document.node_id
        """).on("tagId" -> id).as(long("node_id") ~ long("count") map (flatten) *)

    val nodesWithTaggedDocuments = nodeCounts.map(_._1)
    val nodesWithNoTaggedDocuments = nodeIds.diff(nodesWithTaggedDocuments)
    val zeroCounts = nodesWithNoTaggedDocuments.map((_, 0l))

    nodeCounts ++ zeroCounts
  }

  def loadDocumentList(tagId: Long)(implicit c: Connection): Seq[DocumentListData] = {
    val documentListDataParser = long("document_count") ~ get[Option[Long]]("document_id")

    SQL("""
        SELECT document_count, document_id
        FROM (
          SELECT COUNT(dt.document_id) OVER (PARTITION BY dt.tag_id) AS document_count,
            dt.document_id, RANK() OVER (PARTITION BY dt.tag_id ORDER BY dt.document_id) AS pos
          FROM tag t
          LEFT JOIN document_tag dt ON t.id = dt.tag_id
          WHERE t.id = {tagId}
          ORDER BY t.name, dt.document_id
        ) ss
        WHERE ss.pos < 11
        """).on("tagId" -> tagId).
      as(documentListDataParser map (flatten) *)
  }

}
