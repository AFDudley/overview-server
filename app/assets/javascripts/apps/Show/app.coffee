define [
  'underscore'
  'jquery'
  'backbone'
  './models/TransactionQueue'
  './models/DocumentSet'
  './models/State'
  './controllers/KeyboardController'
  './controllers/ViewsController'
  './controllers/tag_list_controller'
  './controllers/search_result_list_controller'
  './controllers/document_list_controller'
  './controllers/ViewAppController'
  './controllers/TourController'
  './views/TransactionQueueErrorMonitor'
  './views/Mode'
  '../Tree/app'
  '../View/app'
  '../Job/app'
], (_, $, Backbone, \
    TransactionQueue, DocumentSet, State, \
    KeyboardController, \
    ViewsController, tag_list_controller, search_result_list_controller, document_list_controller, \
    ViewAppController, \
    TourController, \
    TransactionQueueErrorMonitor, \
    ModeView, \
    TreeApp, ViewApp, JobApp) ->

  class App
    constructor: (options) ->
      throw 'need options.mainEl' if !options.mainEl

      @el = options.mainEl

      # TODO remove searchDisabled entirely
      @searchDisabled = @el.getAttribute('data-is-searchable') == 'false'
      @tourEnabled = @el.getAttribute('data-tooltips-enabled') == 'true'

      transactionQueue = @_initializeTransactionQueue()
      documentSet = @_initializeDocumentSet(transactionQueue)
      documentSet.views.on('reset', => _.defer(=> @_initializeUi(documentSet)))

    _listenForRefocus: ->
      refocus = ->
        # Pull focus out of the iframe.
        #
        # We can't listen for events on the document iframe; so if it's present,
        # it breaks keyboard shortcuts. We need to re-grab focus whenever we can
        # without disturbing the user.
        #
        # For instance, if the user is logging in to DocumentCloud in the iframe,
        # we don't want to steal focus; so a timer is bad, and a mousemove handler
        # is bad. But if we register a click, it's worth using that to steal focus.
        window.focus() if document.activeElement?.tagName == 'IFRAME'

      refocus_body_on_leave_window = ->
        # Ugly fix for https://github.com/overview/overview-server/issues/321
        hidden = undefined

        callback = (e) ->
          if !document[hidden]
            refocus()

        if document[hidden]?
          document.addEventListener("visibilitychange", callback)
        else if document[hidden = "mozHidden"]?
          document.addEventListener("mozvisibilitychange", callback)
        else if document[hidden = "webkitHidden"]?
          document.addEventListener("webkitvisibilitychange", callback)
        else if document[hidden = "msHidden"]?
          document.addEventListener("msvisibilitychange", callback)
        else
          hidden = undefined

      refocus_body_on_event = ->
        # Ugly fix for https://github.com/overview/overview-server/issues/362
        $('body').on 'click', (e) ->
          refocus()

      refocus_body_on_leave_window()
      refocus_body_on_event()
      undefined

    _listenForResize: (documentEl) ->
      $documentEl = $(documentEl)

      refreshWidth = ->
        # Round the iframe's parent's width, because it needs an integer number of px
        $documentEl.find('iframe')
          .width(1)
          .width($documentEl.width())

      throttledRefreshWidth = _.throttle(refreshWidth, 100)

      $(window).resize(throttledRefreshWidth)

      refreshWidth()

    _buildHtml: ->
      html = """
        <div id="tree-app-left">
          <div id="tree-app-search"></div>
          <div id="tree-app-views"></div>
          <div id="tree-app-view"></div>
          <div id="tree-app-tags"></div>
        </div>
        <div id="tree-app-right">
          <div id="document-list-title"></div>
          <div id="document-list-and-current">
            <div id="document-list"></div>
            <div id="document-current"></div>
          </div>
          <div id="tree-app-tag-this"></div>
        </div>
        <div id="transaction-queue-error-monitor">
        </div>
      """

      $(@el).html(html)

      if @searchDisabled
        $('#tree-app-search').remove()
        $('#tree-app-left').addClass('search-disabled')

      el = (id) -> document.getElementById(id)

      main: @el
      views: el('tree-app-views')
      view: el('tree-app-view')
      tags: el('tree-app-tags')
      search: el('tree-app-search')
      documentList: el('document-list')
      documentListTitle: el('document-list-title')
      tagThis: el('tree-app-tag-this')
      documentCursor: el('document-current')
      document: el('tree-app-document')
      transactionQueueErrorMonitor: el('transaction-queue-error-monitor')

    _initializeTransactionQueue: ->
      transactionQueue = new TransactionQueue()

      # Override Backbone.ajax so all Backbone operations use transactionQueue
      #
      # XXX This means collection.fetch()`.done()` and `.fail()` will not work:
      # we use real Promise objects, not jQuery ones. You can use `success:`
      # and `error:` callbacks, or use the two-argument `.then()`.
      Backbone.ajax = (args...) -> transactionQueue.ajax(args...)

      transactionQueue

    _initializeDocumentSet: (transactionQueue) ->
      documentSetId = +window.location.pathname.split('/')[2]
      new DocumentSet(documentSetId, transactionQueue)
      # We just kicked off the initial server request

    _initializeUi: (documentSet) ->
      documentSet.views.pollUntilStable()

      els = @_buildHtml()
      keyboardController = new KeyboardController(document)

      view = null
      if (m = ///^\/documentsets\/#{documentSet.id}\/([a-zA-Z]+-[0-9]+)$///.exec(document.location.pathname))?
        view = documentSet.views.get(m[1])
      view ||= documentSet.views.at(0)

      state = new State(documentListParams: documentSet.documentListParams(view), view: view)

      state.on 'change:view', (__, view) ->
        return if !view?
        # Change URL so a page refresh brings us to this view
        url = "/documentsets/#{documentSet.id}/#{view.id}"
        window.history?.replaceState(url, '', url)

      controller = new ViewsController(documentSet, documentSet.views, state)
      els.views.appendChild(controller.el)

      new ModeView(el: @el, state: state)

      tag_list_controller
        documentSet: documentSet
        state: state
        el: els.tags

      if !@searchDisabled
        search_result_list_controller
          documentSet: documentSet
          state: state
          el: els.search

      @_listenForRefocus()
      @_listenForResize(els.document)

      document_list_controller(els.documentListTitle, els.documentList, els.tagThis, els.documentCursor, documentSet, state, keyboardController)

      new ViewAppController
        el: els.view
        state: state
        documentSet: documentSet
        transactionQueue: documentSet.transactionQueue
        keyboardController: keyboardController
        viewAppConstructors:
          tree: TreeApp
          view: ViewApp
          job: JobApp
          error: JobApp

      new TransactionQueueErrorMonitor
        model: documentSet.transactionQueue
        el: els.transactionQueueErrorMonitor

      if @tourEnabled
        TourController()
