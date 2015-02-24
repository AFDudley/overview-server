package org.overviewproject.clone

import org.squeryl.KeyedEntity

import org.overviewproject.persistence.DocumentSetIdGenerator
import org.overviewproject.persistence.orm.Schema
import org.overviewproject.test.DbSpecification
import org.overviewproject.tree.orm.{ Document, DocumentSet, DocumentTag, Tag }

class DocumentTagClonerSpec extends DbSpecification {
  implicit object DocumentTagOrdering extends math.Ordering[DocumentTag] {
    override def compare(a: DocumentTag, b: DocumentTag) = {
      val c1 = a.documentId compare b.documentId
      if (c1 == 0) a.tagId compare b.tagId else c1
    }
  }

  "DocumentTagCloner" should {

    trait DocumentTagContext extends DbTestContext {
      import org.overviewproject.postgres.SquerylEntrypoint._
      var sourceDocumentSet: DocumentSet = _
      var cloneDocumentSet: DocumentSet = _
      var sourceDocumentTags: Seq[DocumentTag] = _
      var cloneDocumentTags: Seq[DocumentTag] = _
      
      var tagMapping: Map[Long, Long] = _

      def createDocumentTags(documents: Seq[Document], tags: Seq[Tag]): Seq[DocumentTag] = {
        documents.zip(tags).map { dt =>
          Schema.documents.insert(dt._1)
          Schema.tags.insert(dt._2)

          DocumentTag(dt._1.id, dt._2.id)
        }
      }

      def createMapping(source: Seq[KeyedEntity[Long]], clone: Seq[KeyedEntity[Long]]): Map[Long, Long] =
        source.map(_.id).zip(clone.map(_.id)).toMap

      override def setupWithDb = {
        sourceDocumentSet = Schema.documentSets.insert(DocumentSet(title = "DocumentTagClonerSpec"))
        cloneDocumentSet= Schema.documentSets.insert(DocumentSet(title = "CloneDocumentTagClonerSpec"))
        val sourceIds = new DocumentSetIdGenerator(sourceDocumentSet.id)
        val cloneIds = new DocumentSetIdGenerator(cloneDocumentSet.id)
        
        val sourceDocuments = Seq.tabulate(10)(i => Document(sourceDocumentSet.id, text = Some("text-" + i), id = sourceIds.next))
        val sourceTags = Seq.tabulate(10)(i => Tag(sourceDocumentSet.id, "tag-i", "000000"))
        val cloneDocuments = sourceDocuments.map(_.copy(documentSetId = cloneDocumentSet.id, id = cloneIds.next))
        val cloneTags = sourceTags.map(_.copy(documentSetId = cloneDocumentSet.id))

        sourceDocumentTags = createDocumentTags(sourceDocuments, sourceTags)
        cloneDocumentTags = createDocumentTags(cloneDocuments, cloneTags)

        tagMapping = createMapping(sourceTags, cloneTags)
        
        Schema.documentTags.insert(sourceDocumentTags)
      }

    }

    "clone DocumentTags" in new DocumentTagContext {
      DocumentTagCloner.clone(sourceDocumentSet.id, cloneDocumentSet.id, tagMapping)

      import org.overviewproject.postgres.SquerylEntrypoint._
      val documentTags = Schema.documentTags.allRows.toSeq

      documentTags.sorted must beEqualTo((sourceDocumentTags ++ cloneDocumentTags).sorted)
    }
    
    "don't try to clone if there are no tags" in new DocumentTagContext {
      DocumentTagCloner.clone(sourceDocumentSet.id, cloneDocumentSet.id, Map()) must not(throwA[Exception])
      
    }
    
  }
}
