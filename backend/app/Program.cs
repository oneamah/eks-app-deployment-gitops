using Amazon;
using Amazon.S3;
using Amazon.S3.Model;
using MySqlConnector;

var builder = WebApplication.CreateBuilder(args);

var allowedOrigins = builder.Configuration
    .GetSection("Cors:AllowedOrigins")
    .Get<string[]>()
    ?? [];

var mysqlConnectionString = builder.Configuration.GetConnectionString("DefaultConnection");
var s3BucketName = builder.Configuration["S3:BucketName"];
var s3PublicBaseUrl = builder.Configuration["S3:PublicBaseUrl"]?.TrimEnd('/');
var s3Region = builder.Configuration["S3:Region"]
    ?? builder.Configuration["AWS_REGION"]
    ?? builder.Configuration["AWS_DEFAULT_REGION"]
    ?? "us-east-1";

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
builder.Services.AddSingleton<IAmazonS3>(_ => new AmazonS3Client(RegionEndpoint.GetBySystemName(s3Region)));

var app = builder.Build();

if (!string.IsNullOrWhiteSpace(mysqlConnectionString))
{
    await EnsurePostsTableAsync(mysqlConnectionString);
}

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

app.MapPost("/admin/uploads", async (IAmazonS3 s3Client, IFormFile file) =>
{
    if (string.IsNullOrWhiteSpace(s3BucketName))
    {
        return Results.Problem(
            title: "S3 bucket name is not configured.",
            detail: "Set S3__BucketName in backend environment.",
            statusCode: StatusCodes.Status500InternalServerError);
    }

    if (file.Length == 0)
    {
        return Results.BadRequest(new { message = "File is required." });
    }

    if (file.Length > 10 * 1024 * 1024)
    {
        return Results.BadRequest(new { message = "File is too large. Max size is 10 MB." });
    }

    var safeName = SanitizeFileName(file.FileName);
    var key = $"posts/{DateTime.UtcNow:yyyy/MM}/{Guid.NewGuid():N}-{safeName}";

    try
    {
        await using var stream = file.OpenReadStream();

        var request = new PutObjectRequest
        {
            BucketName = s3BucketName,
            Key = key,
            InputStream = stream,
            ContentType = string.IsNullOrWhiteSpace(file.ContentType) ? "application/octet-stream" : file.ContentType
        };

        await s3Client.PutObjectAsync(request);

        var imageUrl = !string.IsNullOrWhiteSpace(s3PublicBaseUrl)
            ? $"{s3PublicBaseUrl}/{key}"
            : $"https://{s3BucketName}.s3.{s3Region}.amazonaws.com/{key}";

        return Results.Ok(new UploadResponse(key, imageUrl));
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Failed to upload image to S3.",
            detail: ex.Message,
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("UploadPostImage");

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
            INSERT INTO posts (title, content, image_url, created_at)
            VALUES (@title, @content, @imageUrl, UTC_TIMESTAMP());
            SELECT LAST_INSERT_ID();
            """;

        await using var command = new MySqlCommand(insertSql, connection);
        command.Parameters.AddWithValue("@title", request.Title.Trim());
        command.Parameters.AddWithValue("@content", request.Content.Trim());
        command.Parameters.AddWithValue("@imageUrl", string.IsNullOrWhiteSpace(request.ImageUrl) ? DBNull.Value : request.ImageUrl.Trim());

        var idObj = await command.ExecuteScalarAsync();
        var id = Convert.ToInt64(idObj);

        var createdPost = await GetPostByIdAsync(connection, id);
        return createdPost is null ? Results.Problem("Failed to fetch created post.") : Results.Created($"/posts/{id}", createdPost);
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
            SELECT id, title, content, image_url, created_at, updated_at
            FROM posts
            ORDER BY id DESC;
            """;

        await using var command = new MySqlCommand(querySql, connection);
        await using var reader = await command.ExecuteReaderAsync();

        var posts = new List<PostResponse>();

        while (await reader.ReadAsync())
        {
            posts.Add(MapPost(reader));
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

app.MapGet("/posts/{id:long}", async (long id) =>
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

        var post = await GetPostByIdAsync(connection, id);
        return post is null ? Results.NotFound() : Results.Ok(post);
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Failed to fetch post.",
            detail: ex.Message,
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("GetPostById");

app.MapPut("/posts/{id:long}", async (long id, UpdatePostRequest request) =>
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

        const string updateSql = """
            UPDATE posts
            SET title = @title,
                content = @content,
                image_url = @imageUrl,
                updated_at = UTC_TIMESTAMP()
            WHERE id = @id;
            """;

        await using var command = new MySqlCommand(updateSql, connection);
        command.Parameters.AddWithValue("@id", id);
        command.Parameters.AddWithValue("@title", request.Title.Trim());
        command.Parameters.AddWithValue("@content", request.Content.Trim());
        command.Parameters.AddWithValue("@imageUrl", string.IsNullOrWhiteSpace(request.ImageUrl) ? DBNull.Value : request.ImageUrl.Trim());

        var rows = await command.ExecuteNonQueryAsync();
        if (rows == 0)
        {
            return Results.NotFound();
        }

        var updated = await GetPostByIdAsync(connection, id);
        return updated is null ? Results.NotFound() : Results.Ok(updated);
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Failed to update post.",
            detail: ex.Message,
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("UpdatePost");

app.MapDelete("/posts/{id:long}", async (long id) =>
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

        const string deleteSql = "DELETE FROM posts WHERE id = @id;";
        await using var command = new MySqlCommand(deleteSql, connection);
        command.Parameters.AddWithValue("@id", id);
        var rows = await command.ExecuteNonQueryAsync();

        return rows == 0 ? Results.NotFound() : Results.NoContent();
    }
    catch (Exception ex)
    {
        return Results.Problem(
            title: "Failed to delete post.",
            detail: ex.Message,
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("DeletePost");

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

app.MapGet("/weatherforecast", () =>
{
    var forecast = Enumerable.Range(1, 5).Select(index =>
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

    const string createTableSql = """
        CREATE TABLE IF NOT EXISTS posts (
            id BIGINT NOT NULL AUTO_INCREMENT,
            title VARCHAR(255) NOT NULL,
            content TEXT NOT NULL,
            image_url VARCHAR(1024) NULL,
            created_at DATETIME NOT NULL,
            updated_at DATETIME NULL,
            PRIMARY KEY (id)
        );
        """;

    await using var createCommand = new MySqlCommand(createTableSql, connection);
    await createCommand.ExecuteNonQueryAsync();

    await EnsureColumnExistsAsync(connection, "posts", "image_url", "ALTER TABLE posts ADD COLUMN image_url VARCHAR(1024) NULL;");
    await EnsureColumnExistsAsync(connection, "posts", "updated_at", "ALTER TABLE posts ADD COLUMN updated_at DATETIME NULL;");
}

static async Task EnsureColumnExistsAsync(MySqlConnection connection, string tableName, string columnName, string alterSql)
{
    const string checkSql = """
        SELECT COUNT(*)
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = @tableName
          AND COLUMN_NAME = @columnName;
        """;

    await using var checkCommand = new MySqlCommand(checkSql, connection);
    checkCommand.Parameters.AddWithValue("@tableName", tableName);
    checkCommand.Parameters.AddWithValue("@columnName", columnName);

    var countObj = await checkCommand.ExecuteScalarAsync();
    var exists = Convert.ToInt32(countObj) > 0;

    if (exists)
    {
        return;
    }

    await using var alterCommand = new MySqlCommand(alterSql, connection);
    await alterCommand.ExecuteNonQueryAsync();
}

static async Task<PostResponse?> GetPostByIdAsync(MySqlConnection connection, long id)
{
    const string sql = """
        SELECT id, title, content, image_url, created_at, updated_at
        FROM posts
        WHERE id = @id
        LIMIT 1;
        """;

    await using var command = new MySqlCommand(sql, connection);
    command.Parameters.AddWithValue("@id", id);
    await using var reader = await command.ExecuteReaderAsync();

    if (!await reader.ReadAsync())
    {
        return null;
    }

    return MapPost(reader);
}

static PostResponse MapPost(MySqlDataReader reader)
{
    var imageUrlOrdinal = reader.GetOrdinal("image_url");
    var updatedAtOrdinal = reader.GetOrdinal("updated_at");

    return new PostResponse(
        reader.GetInt64("id"),
        reader.GetString("title"),
        reader.GetString("content"),
        reader.IsDBNull(imageUrlOrdinal) ? null : reader.GetString(imageUrlOrdinal),
        reader.GetDateTime("created_at"),
        reader.IsDBNull(updatedAtOrdinal) ? null : reader.GetDateTime(updatedAtOrdinal));
}

static string SanitizeFileName(string fileName)
{
    var invalidChars = Path.GetInvalidFileNameChars();
    var cleaned = new string(fileName.Select(ch => invalidChars.Contains(ch) ? '_' : ch).ToArray());
    return string.IsNullOrWhiteSpace(cleaned) ? "upload.bin" : cleaned;
}

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}

record CreatePostRequest(string Title, string Content, string? ImageUrl);
record UpdatePostRequest(string Title, string Content, string? ImageUrl);
record PostResponse(long Id, string Title, string Content, string? ImageUrl, DateTime CreatedAt, DateTime? UpdatedAt);
record UploadResponse(string Key, string ImageUrl);
