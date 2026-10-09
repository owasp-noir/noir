using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Volo.Abp;
using Volo.Abp.Application.Dtos;

namespace Acme.BookStore.Books;

public class BookAppService : BookStoreAppService, IBookAppService
{
    private readonly IBookRepository _bookRepository;

    public BookAppService(IBookRepository bookRepository)
    {
        _bookRepository = bookRepository;
    }

    public async Task<BookDto> GetAsync(Guid id)
    {
        var book = await _bookRepository.GetAsync(id);
        return ObjectMapper.Map<Book, BookDto>(book);
    }

    public async Task<PagedResultDto<BookDto>> GetListAsync(GetBookListDto input)
    {
        var books = await _bookRepository.GetPagedListAsync(input.SkipCount, input.MaxResultCount, input.Sorting);
        return new PagedResultDto<BookDto>(books.Count, ObjectMapper.Map<List<Book>, List<BookDto>>(books));
    }

    public async Task<BookDto> CreateAsync(CreateBookDto input)
    {
        var book = await _bookRepository.InsertAsync(new Book(input.Name, input.Price));
        return ObjectMapper.Map<Book, BookDto>(book);
    }

    public async Task DeleteAsync(Guid id)
    {
        await _bookRepository.DeleteAsync(id);
    }

    // Unconventional name: POST with the rest of the name as a sub-path.
    public async Task PublishAsync(Guid id, CancellationToken cancellationToken)
    {
        await _bookRepository.PublishAsync(id, cancellationToken);
    }

    // `GetAuthorLookup` -> GET /author-lookup, plus a secondary `{authorId}`.
    public Task<ListResultDto<AuthorLookupDto>> GetAuthorLookupAsync(Guid authorId, string filter)
    {
        return Task.FromResult(new ListResultDto<AuthorLookupDto>());
    }

    [HttpPut("api/books/{id}/price")]
    public Task ChangePriceAsync(Guid id, decimal price)
    {
        return Task.CompletedTask;
    }

    [RemoteService(false)]
    public Task RecalculateAsync()
    {
        return Task.CompletedTask;
    }

    protected Task InternalHelperAsync()
    {
        return Task.CompletedTask;
    }

    public static string Describe(string value) => value;
}
