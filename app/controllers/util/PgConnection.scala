package controllers.util

import play.api.db.DB
import play.api.Play.current
import org.postgresql.PGConnection
import org.overviewproject.postgres.SquerylEntrypoint.using
import org.squeryl.Session
import org.overviewproject.postgres.SquerylPostgreSqlAdapter

trait PgConnection {

    /**
   * Duplicates functionality in TransactionActionController, but in a way that
   * enables us to get a hold of a PGConnection.
   * DB.withConnection gives us a Play AutoCleanConnection, which we can't cast.
   * DB.getConnection gives us a BoneCP ConnectionHandle, which can
   * be converted to the PGConnection we need for dealing with Postgres
   * LargeObjects.
   */
  @deprecated("Use TransactionActionController and java.sql.Connection#unwrap()", "2015-02-25")
  def withPgConnection[A](f: PGConnection => A) = {
    val connection = DB.getConnection(autocommit = false)
    try {
      val adapter = new SquerylPostgreSqlAdapter()
      val session = new Session(connection, adapter)
      using(session) {
        val pgConnection = connection.unwrap(classOf[PGConnection])

        val r = f(pgConnection)
        connection.commit // simply closing the connection does not seem to commit the transaction.
        r
      }
    } finally {
      connection.close
    }
  }
}
