package views.json.api.Document

import play.api.libs.json.{JsArray,JsNumber,JsObject,JsString,JsValue}
import scala.collection.mutable.Buffer

import org.overviewproject.models.Document

object show {
  def apply(document: Document): JsValue = {
    val buf = Buffer[(String,JsValue)](
      "id" -> JsNumber(document.id),
      "title" -> JsString(document.title),
      "keywords" -> JsArray(document.keywords.map(JsString(_))),
      "text" -> JsString(document.text)
    )
    if (document.suppliedId.nonEmpty) {
      buf += ("suppliedId" -> JsString(document.suppliedId))
    }
    if (document.url.getOrElse("") != "") {
      buf += ("url" -> JsString(document.url.getOrElse("")))
    }
    if (document.pageNumber.isDefined) {
      buf == ("page" -> document.pageNumber.getOrElse(-1))
    }
    JsObject(buf)
  }
}
