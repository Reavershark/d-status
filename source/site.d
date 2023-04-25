module site;

struct Category
{
    string name;
    Site[] sites;
}

struct Site
{
    string name;
    string description;
    string author;
    string url;

    int lastCode;
}
