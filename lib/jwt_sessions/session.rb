# frozen_string_literal: true

require 'securerandom'

module JWTSessions
  class Session
    attr_reader :access_token, :refresh_token, :csrf_token
    attr_accessor :payload, :auth_id

    # auth_id is a unique identifier of a token issuer aka user
    def initialize(auth_id, payload = {})
      @auth_id = auth_id
      @payload = payload
    end

    def login
      create_csrf_token
      create_access_token
      create_refresh_token

      tokens_hash
    end

    def masked_csrf(refresh_payload)
      token = retrieve_refresh_token(refresh_payload)
      CsrfToken.new(token.csrf).token
    end

    def all
      RefreshToken.all(auth_id)
    end

    def refresh(refresh_payload, &block)
      retrieve_refresh_token
      check_refresh_on_time(&block) if block_given?

      AccessToken.destroy(@_refresh.access_token_id)

      issue_tokens_after_refresh
    end

    private

    def retrieve_refresh_token(payload)
      id = refresh_payload['id']
      @_refresh = RefreshToken.find(id, auth_id)
      raise Errors::Unauthorized unless @_refresh
      @_refresh
    end

    def tokens_hash
      { csrf: csrf_token, access: access_token, refresh: refresh_token }
    end

    def check_refresh_on_time
      expiration = @_refresh.access_expiration
      yield @_refresh.id, auth_id, expiration if expiration > Time.now
    end

    def issue_tokens_after_refresh
      create_csrf_token
      create_access_token
      update_refresh_token

      tokens_hash
    end

    def update_refresh_token
      @_refresh.update_token(@_access.id, @_access.expires_at, @_csrf.salt)
      @refresh_token = @_refresh.token
    end

    def create_csrf_token
      @_csrf = CsrfToken.create
      @csrf_token = @_csrf.token
    end

    def craete_refresh_token
      @_refresh = RefreshToken.create(auth_uid, @_csrf.salt, @_access.id, @_access.expires_at)
      @refresh_token = @_refresh.token
    end

    def create_access_token
      @_access = AccessToken.create(@_csrf.salt, payload)
      @access_token = @_access.token
      token_payload = payload.merge(token_uid: access_token_uid, exp: access_expiration)
      TokenStore.set_access(access_token_uid, salt, access_expiration)
      Token.encode(token_payload)
    end

    def masked_auth_token(session)
      one_time_pad = SecureRandom.random_bytes(RefreshToken::CSRF_LENGTH)
      encrypted_csrf_token = xor_byte_strings(one_time_pad, Base64.strict_decode64(session[:_csrf_token]))
      masked_token = one_time_pad + encrypted_csrf_token
      Base64.strict_encode64(masked_token)
    end
  end
end