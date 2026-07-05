using MySqlConnector;

var builder = WebApplication.CreateBuilder(args);

var allowedOrigins = builder.Configuration
    .GetSection("Cors:AllowedOrigins")
    .Get<string[]>()
    ?? [];

var mysqlConnectionString = builder.Configuration.GetConnectionString("DefaultConnection");

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();
builder.Services.AddCors(options =>
{
    options.AddPolicy("FrontendCors", policy =>
    {
        if (allowedOrigins.Length == 0)
        {
            return;
        }

        policy.WithOrigins(allowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

var app = builder.Build();

if (!string.IsNullOrWhiteSpace(mysqlConnectionString))
{
    await EnsurePostsTableAsync(mysqlConnectionString);
}

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

if (allowedOrigins.Length > 0)
{
    app.UseCors("FrontendCors");
}

app.MapGet("/health", () => Results.Ok(new
{
    status = "Healthy",
    service = "backend-api",
    timeUtc = DateTime.UtcNow
}))
.WithName("Health");

app.MapGet("/db-health", async () =>
{
    if (string.IsNullOrWhiteSpace(mysqlConnectionString))
    {
        return Results.Problem(
            title: "MySQL connection string is not configured.",
            statusCode: StatusCodes.Status500InternalServerError);
    }

    try
    {
        await using var connection = new MySqlConnection(mysqlConnectionString);
        await connection.OpenAsync();

        await using var command = new MySqlCommand("SELECT 1", connection);
        var result = await command.ExecuteScalarAsync();

        return Results.Ok(new
        {
            status = "Healthy",
            database = "mysql",
            result,
            timeUtc = DateTime.UtcNow
        });
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Failed to connect to MySQL.",
            detail: ex.Message,
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("DatabaseHealth");

app.MapPost("/posts", async (CreatePostRequest request) =>
{
    if (string.IsNullOrWhiteSpace(mysqlConnectionString))
    {
        return Results.Problem(
            title: "MySQL connection string is not configured.",
            statusCode: StatusCodes.Status500InternalServerError);
    }

    if (string.IsNullOrWhiteSpace(request.Title) || string.IsNullOrWhiteSpace(request.Content))
    {
        return Results.BadRequest(new { message = "Title and content are required." });
    }

    try
    {
        await using var connection = new MySqlConnection(mysqlConnectionString);
        await connection.OpenAsync();

        const string insertSql = """
            INSERT INTO posts (title, content, created_at)
            VALUES (@title, @content, UTC_TIMESTAMP());
            SELECT LAST_INSERT_ID();
            """;

        await using var command = new MySqlCommand(insertSql, connection);
        command.Parameters.AddWithValue("@title", request.Title.Trim());
        command.Parameters.AddWithValue("@content", request.Content.Trim());

        var idObj = await command.ExecuteScalarAsync();
        var id = Convert.ToInt64(idObj);

        var createdPost = new PostResponse(
            id,
            request.Title.Trim(),
            request.Content.Trim(),
            DateTime.UtcNow);

        return Results.Created($"/posts/{id}", createdPost);
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Failed to create post.",
            detail: ex.Message,
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("CreatePost");

app.MapGet("/posts", async () =>
{
    if (string.IsNullOrWhiteSpace(mysqlConnectionString))
    {
        return Results.Problem(
            title: "MySQL connection string is not configured.",
            statusCode: StatusCodes.Status500InternalServerError);
    }

    try
    {
        await using var connection = new MySqlConnection(mysqlConnectionString);
        await connection.OpenAsync();

        const string querySql = """
            SELECT id, title, content, created_at
            FROM posts
            ORDER BY id DESC;
            """;

        await using var command = new MySqlCommand(querySql, connection);
        await using var reader = await command.ExecuteReaderAsync();

        var posts = new List<PostResponse>();

        while (await reader.ReadAsync())
        {
            posts.Add(new PostResponse(
                reader.GetInt64("id"),
                reader.GetString("title"),
                reader.GetString("content"),
                reader.GetDateTime("created_at")));
        }

        return Results.Ok(posts);
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Failed to fetch posts.",
            detail: ex.Message,
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("GetPosts");

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

app.MapGet("/weatherforecast", () =>
{
    var forecast =  Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast
        (
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20, 55),
            summaries[Random.Shared.Next(summaries.Length)]
        ))
        .ToArray();
    return forecast;
})
.WithName("GetWeatherForecast");

app.Run();

static async Task EnsurePostsTableAsync(string connectionString)
{
    await using var connection = new MySqlConnection(connectionString);
    await connection.OpenAsync();

    const string sql = """
        CREATE TABLE IF NOT EXISTS posts (
            id BIGINT NOT NULL AUTO_INCREMENT,
            title VARCHAR(255) NOT NULL,
            content TEXT NOT NULL,
            created_at DATETIME NOT NULL,
            PRIMARY KEY (id)
        );
        """;

    await using var command = new MySqlCommand(sql, connection);
    await command.ExecuteNonQueryAsync();
}

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}

record CreatePostRequest(string Title, string Content);
record PostResponse(long Id, string Title, string Content, DateTime CreatedAt);
