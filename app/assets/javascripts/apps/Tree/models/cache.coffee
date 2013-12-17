define [
  'jquery'
  './selection' # deprecated!
  './document_store'
  './on_demand_tree'
  './tag_store'
  './TagLikeApi'
  './search_result_store'
  './needs_resolver'
  './transaction_queue'
  'i18n'
], ($, Selection, DocumentStore, OnDemandTree, TagStore, TagLikeApi, SearchResultStore, NeedsResolver, TransactionQueue, i18n) ->
  t = i18n.namespaced('views.DocumentSet.show.cache')

  Deferred = $.Deferred

  # A Cache stores documents, nodes and tags, plus a transaction queue.
  #
  # Nodes, documents and tags are plain old data objects, stored in
  # @document_store, @tag_store and @on_demand_tree.
  #
  # @transaction_queue can be used to fetch data from the server and
  # send modifications to the server.
  #
  # * add_*, edit_*, remove_*: Add or remove objects from their appropriate
  #   stores. (The methods are here when removals cross boundaries: for example,
  #   removing a tag means all documents must be modified.)
  # * create_*, update_*, delete_*: Update the cache, *and* queue a transaction to
  #   modify the server's data.
  #
  # Lots of these methods are inconsistent and ugly. This whole class needs
  # rethinking and splitting-up.
  class Cache
    constructor: () ->
      @document_store = new DocumentStore()
      @tag_store = new TagStore()
      @search_result_store = new SearchResultStore("#{window.location.pathname}/search-results")
      @needs_resolver = new NeedsResolver(@tag_store, @search_result_store)
      @transaction_queue = new TransactionQueue()
      @server = @needs_resolver.server
      @tag_api = new TagLikeApi(@tag_store, @transaction_queue, "#{window.location.pathname}/tags")
      @search_result_api = new TagLikeApi(@search_result_store, @transaction_queue, "#{window.location.pathname}/searches")
      @on_demand_tree = new OnDemandTree(this) # FIXME this is ugly

    load_root: () ->
      @on_demand_tree.demand_root()

    # Serializes calls to NeedsResolver.get_deferred() through @transaction_queue.
    #
    # FIXME rewrite NeedsResolver & co. This is all very confusing.
    resolve_deferred: () ->
      args = Array.prototype.slice.call(arguments, 0)
      resolver = @needs_resolver

      deferred = new Deferred()

      @transaction_queue.queue ->
        inner_deferred = resolver.get_deferred.apply(resolver, args)
        inner_deferred.done ->
          inner_args = Array.prototype.slice.call(arguments, 0)
          deferred.resolve.apply(deferred, inner_args)
        inner_deferred.fail ->
          inner_args = Array.prototype.slice.call(arguments, 0)
          deferred.reject.apply(deferred, inner_args)

      deferred

    # Requests new node counts from the server, and updates the cache
    #
    # Params:
    #
    # * tag: tag (or tag ID) to refresh.
    # * onlyNodeIds: if set, only refresh a few node IDs. Otherwise, refresh
    #   every loaded node ID.
    refresh_tagcounts: (tag, onlyNodeIds=undefined) ->
      # the ID might change before the transaction begins
      tag = @tag_store.find_by_id(tag) if !tag.id?

      @transaction_queue.queue(=>
        tagId = tag.id # Now the ID is correct
        @_refresh_post('tagCounts', 'tag_node_counts', tagId, onlyNodeIds)
      , 'refresh_tagcounts')

    refresh_untagged: (onlyNodeIds=undefined) ->
      @transaction_queue.queue(=>
        @_refresh_post('tagCounts', 'untagged_node_counts', 0, onlyNodeIds)
      , 'refresh_untagged')

    _refresh_post: (countsKey, endpoint, pathArgument, onlyNodeIds) ->
      nodes = @on_demand_tree.nodes

      node_ids = if onlyNodeIds?
        onlyNodeIds
      else
        _(nodes).keys()

      @server.post(endpoint, {nodes: node_ids.join(',')}, {path_argument: pathArgument})
        .done (data) =>
          i = 0
          while i < data.length
            nodeid = data[i++]
            count = data[i++]

            node = nodes[nodeid]

            if node?
              counts = (node[countsKey] ||= {})

              if count
                counts[pathArgument] = count
              else
                delete counts[pathArgument]

          @on_demand_tree.id_tree.batchAdd(->) # trigger update

          undefined

    refreshSearchResultCounts: (searchResult, onlyNodeIds=undefined) ->
      # The ID might change before the transaction begins
      searchResult = @search_result_store.find_by_id(searchResult) if !searchResult.id?

      @transaction_queue.queue(=>
        searchResultId = searchResult.id # now the ID is correct
        if searchResultId < 0
          $.Deferred().resolve() # when it gets set, we'll refresh again
        else
          @_refresh_post('searchResultCounts', 'search_result_node_counts', searchResultId, onlyNodeIds)
      , 'refreshSearchResultCounts')

    create_tag: (tag, options) ->
      @tag_api.create(tag, options)

    add_tag: (attributes) ->
      @tag_store.add(attributes)

    edit_tag: (tag, new_tag) ->
      @tag_store.change(tag, new_tag)

    update_tag: (tag, new_tag) ->
      this.edit_tag(tag, new_tag)
      @tag_api.update(tag, new_tag)

    remove_tag: (tag) ->
      @document_store.remove_tag_id(tag.id)

      tagid_string = "#{tag.id}"
      nodes = @on_demand_tree.nodes
      @on_demand_tree.id_tree.batchAdd -> # trigger callbacks
        for __, node of nodes
          tagCounts = node.tagCounts
          if tagCounts?[tagid_string]?
            delete tagCounts[tagid_string]

        undefined

      @tag_store.remove(tag)

    delete_tag: (tag) ->
      @remove_tag(tag)
      @tag_api.destroy(tag)

    edit_node: (node, new_node) ->
      @on_demand_tree.id_tree.batchAdd -> # trigger callbacks
        for k, v of new_node
          if !v?
            node[k] = undefined
          else
            node[k] = JSON.parse(JSON.stringify(v))

    update_node: (node, new_node) ->
      id = node.id

      this.edit_node(node, new_node)

      @transaction_queue.queue =>
        @server.post('node_update', new_node, { path_argument: id })

    # Adds the given Tag to all documents specified by the Selection.
    #
    # This only applies to documents in our document_store. The server-side
    # data will remain unchanged.
    addTagToSelectionLocal: (tag, selection) ->
      documents = this._selection_to_documents(selection)
      if documents?
        this._maybe_add_tagid_to_document(tag.id, document) for document in documents

    # Tells the server to add the given Tag to all documents specified by the
    # Selection.
    #
    # This leaves our document_store unaffected.
    addTagToSelectionRemote: (tag, selection) ->
      if @_selection_to_documents(selection)?
        postData = @_selection_to_post_data(selection)
        @transaction_queue.queue(=>
          @server.post('tag_add', postData, { path_argument: tag.id })
        , 'Cache.addTagToSelectionRemote')

    # Adds the given Tag to all documents specified by the Selection.
    #
    # This calls addTagToSelectionLocal() and addTagToSelectionRemote().
    #
    # Return value: a Deferred which will be resolved once the tag has been
    # added.
    addTagToSelection: (tag, selection) ->
      @addTagToSelectionLocal(tag, selection)
      @addTagToSelectionRemote(tag, selection)

    # Removes the given Tag from all documents specified by the Selection.
    #
    # This only applies to documents in our document_store. The server-side
    # data will remain unchanged.
    removeTagFromSelectionLocal: (tag, selection) ->
      documents = this._selection_to_documents(selection)
      if documents?
        @_maybe_remove_tagid_from_document(tag.id, document) for document in documents

    # Tells the server to remove the given Tag to all documents specified by the
    # Selection.
    #
    # This leaves our document_store unaffected.
    removeTagFromSelectionRemote: (tag, selection) ->
      if @_selection_to_documents(selection)?
        postData = @_selection_to_post_data(selection)
        postData = @_selection_to_post_data(selection)
        @transaction_queue.queue =>
          @server.post('tag_remove', postData, { path_argument: tag.id })

    # Removes the given Tag to all documents specified by the Selection.
    #
    # This calls removeTagFromSelectionLocal() and
    # removeTagFromSelectionRemote().
    #
    # Return value: a Deferred which will be resolved once the tag has been
    # removed.
    removeTagFromSelection: (tag, selection) ->
      @removeTagFromSelectionLocal(tag, selection)
      @removeTagFromSelectionRemote(tag, selection)

    # Given a Selection, returns:
    #
    # * [ 'tag', 'Tag name' ] if it's a one-tag selection (ignoring documents)
    # * [ 'node', 'Node description' ] if it's a one-node selection (ignoring
    #   documents)
    # * [ 'searchResult', 'Search query' ] if it's a one-search-result
    #   selection (ignoring documents)
    # * [ 'untagged' ] if it's the special untagged tag
    # * [ 'other' ] if it's something else (or undefined)
    describeSelectionWithoutDocuments: (selection) ->
      nodeCount = selection?.nodes?.length
      tagCount = selection?.tags?.length
      searchCount = selection?.searchResults?.length

      if nodeCount + tagCount + searchCount == 1
        switch
          when nodeCount
            id = selection.nodes[0]
            description = @on_demand_tree.nodes[id]?.description
            [ 'node', description ]
          when tagCount
            id = selection.tags[0]
            if id == 0
              [ 'untagged' ]
            else
              name = @tag_store.find_by_id(id)?.name
              [ 'tag', name ]
          else
            id = selection.searchResults[0]
            query = @search_result_store.find_by_id(id)?.query
            [ 'searchResult', query ]
      else
        [ 'other' ]

    # Returns loaded docids from selection.
    #
    # If nothing is selected, returns undefined. Do not confuse this with
    # the empty-Array return value, which only means we don't have any loaded
    # docids that match the selection.
    _selection_to_documents: (selection) ->
      selection = new Selection(selection) # deprecated!
      return undefined if selection.isEmpty()

      selection.deprecated_documents_from_cache(this)

    _maybe_add_tagid_to_document: (tagid, document) ->
      tagids = document.tagids
      if tagid not in tagids
        tagids.push(tagid)
        @document_store.change(document)

    _maybe_remove_tagid_from_document: (tagid, document) ->
      tagids = document.tagids
      index = tagids.indexOf(tagid)
      if index >= 0
        tagids.splice(index, 1)
        @document_store.change(document)

    _selection_to_post_data: (selection) ->
      selection = new Selection(selection) # deprecated!

      nodes: selection.nodes.join(',')
      documents: selection.documents.join(',')
      tags: selection.tags.join(',')
      searchResults: selection.searchResults.join(',')
