# frozen_string_literal: true

# name: discourse-plugin-discord-auth
# about: Enable Login via Discord
# version: 0.1.3
# authors: Jeff Wong
# url: https://github.com/featheredtoast/discourse-plugin-discord-auth

require 'auth/oauth2_authenticator'
require 'open-uri'
require 'json'

gem 'omniauth-discord', '0.1.8'

register_svg_icon "fab-discord" if respond_to?(:register_svg_icon)

enabled_site_setting :discord_enabled

class DiscordAuthenticator < ::Auth::OAuth2Authenticator
  PLUGIN_NAME = 'oauth-discord'
  BASE_API_URL = 'https://discordapp.com/api'

  def name
    'discord'
  end

  def enabled?
    SiteSetting.discord_enabled?
  end

  def after_authenticate(auth_token)
    result = super
    data = auth_token[:info]
    result.extra_data[:avatar_url] = data[:image]
    if (avatar_url = data[:image]).present?
      retrieve_avatar(result.user, avatar_url)
    end
    result.email = "discord:#{auth_token[:uid]}"
    result.extra_data[:auto_approve] = true
    result
  end

  def after_create_account(user, auth)
    super
    data = auth[:extra_data]
    if !user.approved && data[:auto_approve]
      user.approve(-1, false)
    end
    if (avatar_url = data[:avatar_url]).present?
      retrieve_avatar(user, avatar_url)
    end
  end

  def register_middleware(omniauth)
    omniauth.provider :discord,
                      scope: 'identify',
                      setup: lambda { |env|
                        strategy = env['omniauth.strategy']
                        strategy.options[:client_id] = SiteSetting.discord_client_id
                        strategy.options[:client_secret] = SiteSetting.discord_secret
                      }
  end

  protected

  def retrieve_avatar(user, avatar_url)
    return unless user
    return if user.user_avatar.try(:custom_upload_id).present?
    Jobs.enqueue(:download_avatar_from_url, url: avatar_url, user_id: user.id, override_gravatar: false)
  end
end

auth_provider title: 'with Discord',
              message: 'Log in via Discord',
              frame_width: 920,
              frame_height: 800,
              authenticator: DiscordAuthenticator.new('discord',
                                                          trusted: true,
                                                          auto_create_account: true)

register_css <<CSS

.btn-social.discord {
  background: #7289da;
}

CSS
