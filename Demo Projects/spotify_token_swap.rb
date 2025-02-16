require 'sinatra'
require 'net/http'
require 'net/https'
require 'base64'
require 'json'
require 'sqlite3'

# This is an example token swap service written
# as a Ruby/Sinatra service. This is required by
# the iOS SDK to authenticate a user.
#
# The service requires the Sinatra gem be installed:
#
# $ gem install sinatra
#
# To run the service, enter your client ID, client
# secret and client callback URL below and run the
# project.
#
# $ ruby spotify_token_swap.rb
#
# IMPORTANT: The example credentials will work for the
# example apps, you should use your own in your real
# environment. as these might change at any time.
#
# Once the service is running, pass the public URI to
# it (such as http://localhost:1234/swap if you run it
# with default settings on your local machine) to the
# token swap method in the iOS SDK:
#
# NSURL *swapServiceURL = [NSURL urlWithString:@"http://localhost:1234/swap"];
#
# -[SPAuth handleAuthCallbackWithTriggeredAuthURL:url
#                   tokenSwapServiceEndpointAtURL:swapServiceURL
#                                        callback:callback];
#

print "\e[31m------------------------------------------------------\e[0m\n"
print "\e[31mYou're using example credentials, please replace these\e[0m\n"
print "\e[31mwith your own and remove this silly warning.\e[0m\n"
print "\e[31m------------------------------------------------------\e[0m\n"
print "\7\7"
sleep(2)
CLIENT_ID = "e6695c6d22214e0f832006889566df9c"
CLIENT_SECRET = "29eb02041ba646179a1189dccac112c7"
CLIENT_CALLBACK_URL = "spotifyiossdkexample://"
AUTH_HEADER = "Basic " + Base64.strict_encode64(CLIENT_ID + ":" + CLIENT_SECRET)
SPOTIFY_ACCOUNTS_ENDPOINT = URI.parse("https://accounts.spotify.com")
SPOTIFY_API_ENDPOINT = URI.parse("https://api.spotify.com")

set :port, 1234 # The port to bind to.
set :bind, '0.0.0.0' # IP address of the interface to listen on (all)

# A DB for storing refresh tokens for user access tokens.
db = SQLite3::Database.new("spotify_token_swap.db")

db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS user_token (
        username TEXT,
        refresh_token TEXT
    );
    CREATE INDEX IF NOT EXISTS username_index ON user_token (username);
SQL

post '/swap' do

    # This call takes a single POST parameter, "code", which
    # it combines with your client ID, secret and callback
    # URL to get an OAuth token from the Spotify Auth Service,
    # which it will pass back to the caller in a JSON payload.

    auth_code = params[:code]

    http = Net::HTTP.new(SPOTIFY_ACCOUNTS_ENDPOINT.host, SPOTIFY_ACCOUNTS_ENDPOINT.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new("/api/token")

    request.add_field("Authorization", AUTH_HEADER)

    request.form_data = {
        "grant_type" => "authorization_code",
        "redirect_uri" => CLIENT_CALLBACK_URL,
        "code" => auth_code
    }

    response = http.request(request)

    if response.code.to_i == 200
        token_data = JSON.parse(response.body)
        profile_data = get_profile_data(token_data["access_token"])
        db.execute("DELETE FROM user_token WHERE username = (?)", profile_data["id"])
        # Store user ID and refresh token in DB, so that we can retrieve it later.
        db.execute("INSERT INTO user_token (username, refresh_token) VALUES (?, ?)",
            profile_data["id"], token_data["refresh_token"])
    end

    status response.code.to_i
    return response.body
end

post '/refresh' do

    # Request a new access token using the POST:ed access token
    # by looking up the corresponding refresh token in the DB.

    http = Net::HTTP.new(SPOTIFY_ACCOUNTS_ENDPOINT.host, SPOTIFY_ACCOUNTS_ENDPOINT.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new("/api/token")

    request.add_field("Authorization", AUTH_HEADER)

    refresh_token = db.get_first_value("SELECT refresh_token FROM user_token WHERE username = ?", params[:id])

    request.form_data = {
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token
    }

    response = http.request(request)

    status response.code.to_i
    return response.body

end

def get_profile_data(access_token)

    http = Net::HTTP.new(SPOTIFY_API_ENDPOINT.host, SPOTIFY_API_ENDPOINT.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new("/v1/me")
    request.add_field("Authorization", "Bearer " + access_token)
    response = http.request(request)

    return JSON.parse(response.body)

end