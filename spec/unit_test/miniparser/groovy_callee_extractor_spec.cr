require "../../spec_helper"
require "../../../src/miniparsers/groovy_callee_extractor"

describe Noir::GroovyCalleeExtractor do
  it "extracts receiver, framework command, and bare calls" do
    body = <<-GROOVY
      def books = bookService.list()
      AuditLog.write('book.index', books)
      render view: 'index', model: [books: books]
      respond bookService.create(params)
      redirect(action: 'show', id: book.id)
      getBook().toString()
      GROOVY

    callees = Noir::GroovyCalleeExtractor.callees_for_body(body, "BookController.groovy", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"bookService.list", 10},
      {"AuditLog.write", 11},
      {"render", 12},
      {"respond", 13},
      {"bookService.create", 13},
      {"redirect", 14},
      {"getBook", 15},
    ])
  end

  it "skips comments, strings, constructors, and declarations" do
    body = <<-GROOVY
      def ignored = "Ignored.string()"
      def triple = '''
        Ignored.triple()
      '''
      def escapedTriple = """Ignored.escapedTriple(\\""")"""
      def slashy = /Ignored.slashy({})/
      def dollarSlashy = $/Ignored.dollar({}) $/$ Still.ignored()/$
      /* Ignored.block() */
      // Ignored.line()
      def book = new Book()
      def helper()
      Real.call()
      GROOVY

    callees = Noir::GroovyCalleeExtractor.callees_for_body(body, "BookController.groovy", 30)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"Real.call", 41},
    ])
  end

  it "keeps Groovy with calls" do
    body = <<-GROOVY
      with {
        service.call()
      }
      GROOVY

    callees = Noir::GroovyCalleeExtractor.callees_for_body(body, "BookController.groovy", 45)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"with", 45},
      {"service.call", 46},
    ])
  end

  it "extracts safe navigation, spread, and keyword command calls" do
    body = <<-GROOVY
      return render view: 'show', model: [book: bookService?.find(id)]
      books*.save()
      throw notFound params.id
      GROOVY

    callees = Noir::GroovyCalleeExtractor.callees_for_body(body, "BookController.groovy", 55)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"render", 55},
      {"bookService.find", 55},
      {"books.save", 56},
      {"notFound", 57},
    ])
  end

  it "extracts command-style dotted calls" do
    body = <<-GROOVY
      AuditLog.write 'book.update', book
      def saved = BookService.save params
      GROOVY

    callees = Noir::GroovyCalleeExtractor.callees_for_body(body, "BookController.groovy", 60)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"AuditLog.write", 60},
      {"BookService.save", 61},
    ])
  end
end
