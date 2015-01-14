define [
  'backbone'
  'apps/Show/models/State'
], (Backbone, State) ->
  describe 'apps/Show/models/State', ->
    describe 'resetDocumentListParams', ->
      beforeEach ->
        @params2 = 
          equals: sinon.stub().returns(false)
          type: 'params2'

        @params1 =
          equals: sinon.stub().returns(false)
          type: 'params1'
          reset:
            bySomething: sinon.stub().returns(@params2)

      it 'should do nothing when setting to equivalent documentListParams', ->
        state = new State(documentListParams: @params1, document: 'foo')
        @params1.equals.returns(true)
        state.on('all', spy = sinon.spy())
        state.resetDocumentListParams().bySomething()
        expect(spy).not.to.have.been.called
        expect(state.get('document')).to.eq('foo')

      it 'should change document to null when changing documentListParams', ->
        state = new State(documentListParams: @params1, document: 'foo')
        @params1.equals.returns(false)
        state.resetDocumentListParams().bySomething()
        expect(state.get('document')).to.be.null

      it 'should change highlightedDocumentListParams to the new value when changing documentListParams to a tag', ->
        state = new State(documentListParams: @params1)
        @params1.equals.returns(false)
        state.resetDocumentListParams().bySomething()
        expect(state.get('highlightedDocumentListParams')).to.have.property('type', 'params2')

      it 'should not change highlightedDocumentListParams when changing documentListParams to a node', ->
        state = new State(documentListParams: @params1, highlightedDocumentListParams: @params1)
        @params1.reset.bySomething.returns(type: 'node')
        @params1.equals.returns(false)
        state.resetDocumentListParams().bySomething()
        expect(state.get('highlightedDocumentListParams')).to.have.property('type', 'params1')

    describe 'document and oneDocumentSelected', ->
      state = undefined

      beforeEach ->
        state = new State
          document: null
          oneDocumentSelected: false
          documentListParams:
            toJSON: -> { nodes: [ 1 ] }
            reset:
              byDocument: (x) ->
                toJSON: -> [ 'byDocument', x ]

      it 'should give empty selection when document is null and oneDocumentSelected is true', ->
        state.set(document: null, oneDocumentSelected: true)
        expect(state.getSelection().toJSON()).to.deep.eq([ 'byDocument', null ])

      it 'should give document selection when document is set and oneDocumentSelected is true', ->
        state.set(document: 'foo', oneDocumentSelected: true)
        expect(state.getSelection().toJSON()).to.deep.eq([ 'byDocument', 'foo' ])

      it 'should give doclist selection when document is null and oneDocumentSelected is false', ->
        state.set(document: null, oneDocumentSelected: false)
        expect(state.getSelection().toJSON()).to.deep.eq({ nodes: [ 1 ] })

      it 'should give doclist selection when document is set and oneDocumentSelected is false', ->
        state.set(document: 'foo', oneDocumentSelected: false)
        expect(state.getSelection().toJSON()).to.deep.eq({ nodes: [ 1 ] })

    describe 'setView', ->
      class DocumentSet

      class View extends Backbone.Model

      beforeEach ->
        @documentSet = new DocumentSet()
        @view1 = new View(id: 'foo', rootNodeId: 1) # see State.coffee for why we need rootNodeId
        @view2 = new View(id: 'bar', rootNodeId: 2)

        @params =
          documentSet: @documentSet
          view: @view1
          reset:
            withView: (view) =>
              all: =>
                documentSet: @documentSet
                view: view

        @state = new State
          view: @view1
          documentListParams: @params
          document: 'document'
          oneDocumentSelected: true
        @state.setView(@view2)

      it 'should alter view', -> expect(@state.get('view')).to.eq(@view2)
      it 'should unset document', -> expect(@state.get('document')).to.be.null
      it 'should unset oneDocumentSelected', -> expect(@state.get('oneDocumentSelected')).to.be.false

      it 'should alter documentListParams', ->
        params = @state.get('documentListParams')
        expect(params.documentSet).to.eq(@documentSet)
        expect(params.view).to.eq(@view2)
