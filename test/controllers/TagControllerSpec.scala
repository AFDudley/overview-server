package controllers

import play.api.libs.json.Json
import org.specs2.matcher.JsonMatchers
import org.specs2.specification.Scope
import scala.concurrent.Future

import controllers.backend.{SelectionBackend,TagBackend,TagDocumentBackend}
import org.overviewproject.models.Tag
import org.overviewproject.test.factories.PodoFactory

class TagControllerSpec extends ControllerSpecification with JsonMatchers {
  class BaseScope extends Scope {
    val mockStorage = mock[TagController.Storage]
    val mockSelectionBackend = mock[SelectionBackend]
    val mockTagBackend = mock[TagBackend]
    val mockTagDocumentBackend = mock[TagDocumentBackend]
    val controller = new TagController {
      override val storage = mockStorage
      override val selectionBackend = mockSelectionBackend
      override val tagBackend = mockTagBackend
      override val tagDocumentBackend = mockTagDocumentBackend
    }

    val factory = PodoFactory
  }

  "#create" should {
    trait CreateScope extends BaseScope {
      val documentSetId = 1L
      val formBody: Seq[(String,String)] = Seq("name" -> "foo", "color" -> "#123abc")
      def request = fakeAuthorizedRequest.withFormUrlEncodedBody(formBody: _*)
      lazy val result = controller.create(documentSetId)(request)

      def createTag: Tag = factory.tag()

      mockTagBackend.create(any, any) returns Future(createTag)
    }

    "return 400 Bad Request on invaild form body" in new CreateScope {
      override val formBody = Seq("name" -> "foo", "color" -> "bar")
      h.status(result) must beEqualTo(h.BAD_REQUEST)
      there was no(mockTagBackend).create(any, any)
    }

    "create a Tag" in new CreateScope {
      override val formBody = Seq("name" -> "foo", "color" -> "#123abc")
      h.status(result)
      there was one(mockTagBackend).create(documentSetId, Tag.CreateAttributes("foo", "123abc"))
    }

    "return the created Tag" in new CreateScope {
      override def createTag = factory.tag(id=2L, name="blah", color="abc123")
      h.status(result) must beEqualTo(h.CREATED)

      val json = h.contentAsString(result)
      json must /("id" -> 2)
      json must /("name" -> "blah")
      json must /("color" -> "#abc123")
    }
  }

  "#update" should {
    trait UpdateScope extends BaseScope {
      val documentSetId = 1L
      val tagId = 2L
      val formBody: Seq[(String,String)] = Seq("name" -> "foo", "color" -> "#123abc")
      def request = fakeAuthorizedRequest.withFormUrlEncodedBody(formBody: _*)
      lazy val result = controller.update(documentSetId, tagId)(request)

      mockTagBackend.update(any, any, any) returns Future.successful(Some(factory.tag()))
    }

    "return 400 Bad Request on invaild form body" in new UpdateScope {
      override val formBody = Seq("name" -> "foo", "color" -> "bar")
      h.status(result) must beEqualTo(h.BAD_REQUEST)
      there was no(mockTagBackend).create(any, any)
    }

    "return 404 Not Found when not found" in new UpdateScope {
      mockTagBackend.update(any, any, any) returns Future.successful(None)
      h.status(result) must beEqualTo(h.NOT_FOUND)
    }

    "update a Tag" in new UpdateScope {
      override val formBody = Seq("name" -> "foo", "color" -> "#123abc")
      h.status(result)
      there was one(mockTagBackend).update(documentSetId, tagId, Tag.UpdateAttributes("foo", "123abc"))
    }

    "return the updated Tag" in new UpdateScope {
      mockTagBackend.update(any, any, any) returns Future.successful(Some(factory.tag(id=2L, name="foo", color="abc123")))
      h.status(result) must beEqualTo(h.OK)

      val json = h.contentAsString(result)
      json must /("id" -> 2)
      json must /("name" -> "foo")
      json must /("color" -> "#abc123")
    }
  }

  "#destroy" should {
    trait DestroyScope extends BaseScope {
      val documentSetId = 1L
      val tagId = 2L
      lazy val result = controller.destroy(documentSetId, tagId)(fakeAuthorizedRequest)

      mockTagBackend.destroy(any, any) returns Future.successful(Unit)
    }

    "return 204 No Content" in new DestroyScope {
      h.status(result) must beEqualTo(h.NO_CONTENT)
    }

    "delete the tag" in new DestroyScope {
      h.status(result)
      there was one(mockTagBackend).destroy(documentSetId, tagId)
    }
  }

  "indexJson" should {
    class IndexJsonScope extends BaseScope {
      val documentSetId = 1L
      def tagsWithCounts : Seq[(Tag,Long)] = Seq()
      mockStorage.findTagsWithCounts(anyInt) answers { (_) => tagsWithCounts }
      val result = controller.indexJson(documentSetId)(fakeAuthorizedRequest)
    }

    "show an empty list" in new IndexJsonScope {
      h.status(result) must beEqualTo(h.OK)
      h.contentAsString(result) must beEqualTo("[]")
    }

    "prevent caching of result" in new IndexJsonScope {
      h.header(h.CACHE_CONTROL, result) must beSome("max-age=0")
    }

    "show a full list" in new IndexJsonScope {
      override def tagsWithCounts = Seq(
        (Tag(documentSetId=documentSetId, id=1, name="tag1", color="111111") -> 5L),
        (Tag(documentSetId=documentSetId, id=2, name="tag2", color="222222") -> 10L)
      )
      h.status(result) must beEqualTo(h.OK)
      h.contentAsJson(result) must beEqualTo(Json.arr(
        Json.obj("id" -> 1, "name" -> "tag1", "color" -> "#111111", "size" -> 5),
        Json.obj("id" -> 2, "name" -> "tag2", "color" -> "#222222", "size" -> 10)
      ))
    }
  }

  "indexJsonWithTree" should {
    class IndexJsonWithTreeScope extends BaseScope {
      val documentSetId = 1L
      val treeId = 2L
      def tagsWithCounts : Seq[(Tag,Long,Long)] = Seq()
      mockStorage.findTagsWithCounts(anyInt, anyInt) answers { (_) => tagsWithCounts }
      val result = controller.indexJsonWithTree(documentSetId, treeId)(fakeAuthorizedRequest)
    }

    "show an empty list" in new IndexJsonWithTreeScope {
      h.status(result) must beEqualTo(h.OK)
      h.contentAsString(result) must beEqualTo("[]")
    }

    "prevent caching of result" in new IndexJsonWithTreeScope {
      h.header(h.CACHE_CONTROL, result) must beSome("max-age=0")
    }

    "show a full list" in new IndexJsonWithTreeScope {
      override def tagsWithCounts = Seq(
        (Tag(documentSetId=documentSetId, id=1, name="tag1", color="111111"), 5L, 5L),
        (Tag(documentSetId=documentSetId, id=2, name="tag2", color="222222"), 10L, 8L)
      )
      h.status(result) must beEqualTo(h.OK)
      h.contentAsJson(result) must beEqualTo(Json.arr(
        Json.obj("id" -> 1, "name" -> "tag1", "color" -> "#111111", "size" -> 5, "sizeInTree" -> 5),
        Json.obj("id" -> 2, "name" -> "tag2", "color" -> "#222222", "size" -> 10, "sizeInTree" -> 8)
      ))
    }
  }
}
