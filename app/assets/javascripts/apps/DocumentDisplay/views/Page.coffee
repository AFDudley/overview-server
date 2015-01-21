define [
  'underscore'
  'backbone'
  'i18n'
], (_, Backbone, i18n) ->
  TWITTER_WIDGETS_URL = '//platform.twitter.com/widgets.js'
  # Scrolling usually leaves a bit of what *was* visible still visible, to
  # help viewers read those last lines. These two variables help decide how
  # many pixels should remain visible after a scroll
  PAGE_KEY_FRACTION = 0.8 # max percentage of an element that should scroll away
  PAGE_KEY_MARGIN = 100 # min px that should remain visible

  t = i18n.namespaced('views.Document.show')

  Backbone.View.extend
    className: 'document'

    events:
      'click a.boolean-preference': 'onClickBooleanPreference'

    templates:
      # Shows a preference.
      #
      # Parameters:
      # * pref: preference name, e.g. "sidebar"
      # * enabled: true if the pref is enabled; false otherwise
      # * t: scoped i18n function. Will be called with, e.g., "sidebar.enable"
      #
      # Note that the t() call is "backward": for instance, when showing the
      # sidebar pref and it's enabled, t("sidebar.disable") will be the link.
      # That's because these links describe what will happen on click.
      #
      # Any ".document-text" in the result will get filled in with the document
      # text (which may be requested separately).
      showBooleanPref: _.template("""
        <a href="#" class="boolean-preference" data-preference="<%- pref %>" data-enabled="<%= enabled && 'true' || 'false' %>">
          <%- t(pref + '.' + (enabled && 'disable' || 'enable')) %>
        </a>
      """)

      documentCloud: _.template("""
        <ul class="actions">
          <li><%= showBooleanPref('sidebar') %></li>
        </ul>
        <div class="page type-documentcloud">
          <iframe class="document" src="<%- url.url + '?sidebar=' + (getPref('sidebar') && 'true' || 'false') + (url.page || '') %>"></iframe>
        </div>
      """)

      twitter: _.template("""
        <div class="page type-twitter">
          <div class="twitter-tweet-container">
            <blockquote class="twitter-tweet" data-tweet-id="<%- url.id %>">
              <p class="document-text"></p>
              &mdash;<%- url.username %>
              <a href="<%- url.url %>">...</a>
            </blockquote>
          </div>
        </div>
      """)

      facebook: _.template("""
        <div class="page type-facebook">
          <p class="source">
            <span class="label"><%- t('source') %></span>
            <a href="<%- url.url %>" target="_blank"><%- url.url %></a>
          </p>
          <pre class="document-text wrap"></pre>
        </div>
      """)

      localObject: _.template("""
        <div class="page type-local">
          <object data="<%- url.url + '#scrollbar=1&toolbar=1&navpanes=1&view=FitH' %>" type="application/pdf" width="100%" height="100%">
            <div class='missing-plugin'>
              <a href="<%- url.url %>"><i class="icon-cloud-download"></i></a>
              <%= t('missing_plugin') %>
            </div>
          </object>
        </div>
      """)

      secure: _.template("""
        <ul class="actions">
          <% if (!getPref('iframe')) { %>
            <!-- show wrap before iframe, so iframe doesn't move when disabled -->
            <li><%= showBooleanPref('wrap') %></li>
          <% } %>
          <li><%= showBooleanPref('iframe') %></li>
        </ul>
        <div class="page type-secure">
          <p class="source">
            <span class="label"><%- t('source') %></span>
            <a href="<%- url.url %>" target="_blank"><%- url.url %></a>
          </p>
          <% if (!getPref('iframe')) { %>
            <pre class="document-text <%- getPref('wrap') && 'wrap' || 'nowrap' %>"></pre>
          <% } else { %>
            <iframe class="document"  src="<%- url.url %>" width="100" height="100"></iframe>
          <% } %>
        </div>
      """)

      insecure: _.template("""
        <ul class="actions">
          <li><%= showBooleanPref('wrap') %></li>
        </ul>
        <div class="page type-insecure">
          <p class="source">
            <span class="label"><%- t('source') %></span>
            <a href="<%- url.url %>" target="_blank"><%- url.url %></a>
          </p>
          <pre class="document-text <%- getPref('wrap') && 'wrap' || 'nowrap' %>"></pre>
        </div>
      """)

      default: _.template("""
        <ul class="actions">
          <li><%= showBooleanPref('wrap') %></li>
        </ul>
        <div class="page type-default">
          <pre class="document-text <%- getPref('wrap') && 'wrap' || 'nowrap' %>"></pre>
        </div>
      """)

    postRender:
      twitter: ->
        # Twitter's API is undocumented. It goes like this:
        #
        # * On load, twttr.widgets.load() is called (and can't be stopped?).
        #   It replaces any blockquote.twitter-tweet with a tweet, using the
        #   URL in the <a> tag. If the tweet can't be loaded, the blockquote
        #   stays. When the tweet loads, the blockquote is removed.
        #
        # * After load, twttr.widgets.load() can't be called again. But we can
        #   call twttr.widgets.createTweetEmbed(). This accepts an ID, a DOM
        #   element, and an on-finished callback. It appends an iframe to the
        #   DOM element then calls the callback. No iframe, no callback.
        #
        # There's no error-handling.
        if !@twttrLoad?
          # First load. Twitter will automatically find the blockquote and
          # apply itself to it.
          @twttrLoad = $.getScript(TWITTER_WIDGETS_URL)
        else if !twttr?.widgets?.loaded
          # Twitter still hasn't loaded; it will soon, and when it does it will
          # find and change the blockquote
        else
          # Twitter is loaded
          blockquote = @$('blockquote')[0]
          id = blockquote.getAttribute('data-tweet-id')

          twttr.widgets.createTweetEmbed id, blockquote.parentNode, ->
            $(blockquote).remove()

        # Sometimes Twitter doesn't load or doesn't return a tweet--if it's
        # private or if it was deleted.
        #
        # Show the block quote after a delay. This will only be noticeable when
        # the blockquote is still in the DOM -- meaning Twitter isn't feeding us
        # the tweet.
        #
        # From a 1hr search, it seems impossible to detect a failure from
        # Twitter's JavaScript--and the iframe-insertion happens asynchronously.
        # So there's nothing better than this.
        #
        # If the embed succeeds, the blockquote will not be on the page.
        window.setTimeout((-> $(blockquote).show()), 1000)

    initialize: () ->
      @model.on('change:document', => @render())
      @preferences = @model.get('preferences')
      @preferences.on('change', => @render())
      @render()

    render: () ->
      document = @model.get('document')

      type = undefined

      html = if document?.urlProperties?
        preferences = @model.get('preferences')
        getPref = (pref) => preferences.getPreference(pref)
        showBooleanPref = (pref) =>
          @templates.showBooleanPref(
            pref: pref
            enabled: getPref(pref)
            t: t
          )

        url = document.urlProperties
        type = url.type
        template = @templates[type] || @templates.default

        html = template
          document: document
          url: document.urlProperties
          t: t
          getPref: getPref
          showBooleanPref: showBooleanPref
      else
        ''

      @$el.html(html)

      $text = @$('.document-text')
      if $text.length
        document.getText().then((text) -> $text.text(text))

      @postRender[type]?.call(this) if type

    onClickBooleanPreference: (e) ->
      e.preventDefault()
      a = e.currentTarget
      key = a.getAttribute('data-preference')
      wasEnabled = a.getAttribute('data-enabled') == 'true'
      @preferences.setPreference(key, !wasEnabled)
