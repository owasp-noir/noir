import "@typespec/http";

using Http;

@server("https://api.example.com/v1", "Production")
namespace PetStore;

model Pet {
  id: string;
  name: string;
  breed?: string;
}

@route("/pets")
interface Pets {
  @get list(@query filter?: string, @query limit?: int32): Pet[];

  @post create(@body pet: Pet): Pet;

  @route("{id}") @get read(@path id: string, @header("X-Trace-Id") traceId?: string): Pet;

  @route("{id}/avatar")
  @post
  upload(@path id: string, @body file: bytes): void;
}

@route("/health")
@get
op health(): string;
