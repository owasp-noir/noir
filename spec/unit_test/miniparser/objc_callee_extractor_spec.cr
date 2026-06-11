require "../../spec_helper"
require "../../../src/miniparsers/objc_callee_extractor"

describe Noir::ObjcCalleeExtractor do
  it "extracts message-send selectors (incl. nested) from an Objective-C body" do
    body = <<-OBJC
      [self performMagicLinkAuthenticationWith:url];
      if ([self handleOpenNoteWithUrl:url]) { return YES; }
      NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
      if ([[c host] isEqualToString:@"new"]) {
          Note *n = [[SPObjectManager sharedManager] newNoteWithContent:body tags:tags];
          [self presentNote:n animated:NO];
      }
      OBJC

    names = Noir::ObjcCalleeExtractor.callees_for_body(body, "SPAppDelegate.m", 1).map { |n, _, _| n }
    names.should contain("performMagicLinkAuthenticationWith")
    names.should contain("handleOpenNoteWithUrl")
    names.should contain("componentsWithURL")
    names.should contain("host") # `[c host]` no-arg message
    names.should contain("isEqualToString")
    names.should contain("sharedManager")      # inner of a nested send
    names.should contain("newNoteWithContent") # outer of a nested send
    names.should contain("presentNote")
  end

  it "captures the dispatch selectors in a handler-loop body" do
    body = <<-OBJC
      for (id<VLCURLHandler> handler in URLHandlers.handlers) {
          if ([handler canHandleOpenWithUrl:url options:options]) {
              return [handler performOpenWithUrl:url options:options];
          }
      }
      OBJC

    names = Noir::ObjcCalleeExtractor.callees_for_body(body, "VLCAppDelegate.m", 1).map { |n, _, _| n }
    names.should contain("canHandleOpenWithUrl")
    names.should contain("performOpenWithUrl")
  end

  it "ignores control flow, memory-management selectors, and subscripts" do
    body = <<-OBJC
      // open the note
      id obj = arr[0];
      NSString *s = dict[@"key"];
      Foo *f = [[Foo alloc] init];
      if (obj) { [obj doRealWork:s]; }
      OBJC

    names = Noir::ObjcCalleeExtractor.callees_for_body(body, "X.m", 1).map { |n, _, _| n }
    names.should contain("doRealWork")
    names.should_not contain("if")
    names.should_not contain("alloc")
    names.should_not contain("init")
    # `arr[0]` / `dict[@"key"]` subscripts are not message sends
    names.should_not contain("arr")
    names.should_not contain("dict")
  end
end
