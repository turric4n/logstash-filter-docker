using Docker.DotNet;
using Microsoft.Extensions.Caching.Memory;

System.Globalization.CultureInfo.DefaultThreadCurrentCulture = System.Globalization.CultureInfo.InvariantCulture;
System.Globalization.CultureInfo.DefaultThreadCurrentUICulture = System.Globalization.CultureInfo.InvariantCulture;

var builder = WebApplication.CreateBuilder(args);

// Register memory cache
builder.Services.AddMemoryCache();

var app = builder.Build();

app.MapGet("/docker-services", async (IMemoryCache cache) =>
{
    const string cacheKey = "docker-services";

    if (cache.TryGetValue(cacheKey, out object result)) return Results.Ok(result);

    using var dockerClient = new DockerClientConfiguration(new Uri("unix:///var/run/docker.sock")).CreateClient();
    var services = await dockerClient.Swarm.ListServicesAsync();
    result = services.Select(s => new
    {
        s.ID,
        Name = s.Spec.Name,
        Labels = s.Spec.Labels
    }).ToList();

    // Set cache for 5 minutes
    cache.Set(cacheKey, result, TimeSpan.FromMinutes(5));
    return Results.Ok(result);
});


app.Run();