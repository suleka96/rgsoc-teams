require 'feedzirra'

class Feed
  autoload :Discovery, 'feed/discovery'
  autoload :Image,     'feed/image'
  autoload :Item,      'feed/item'
  autoload :S3,        'feed/s3'

  class << self
    def update_all
      Source.where(kind: 'blog').each do |source|
        new(source).update
      end
    end
  end

  attr_reader :source

  def initialize(source)
    @source = source
    Feed::S3.setup(access_key_id: ENV['AWS_ACCESS_KEY_ID'], secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'])
  end

  def update
    source.update_attributes!(title: discover_title) unless source.title.present?
    source.feed_url = discover_feed_url unless source.feed_url.present?
    update_entries
    source.save! if source.feed_url_changed? && source.feed_url != source.url
  rescue => e
    puts e.message
    puts e.backtrace
  end

  private

    def discover_title
      title = Discovery.new(source.url).title
      puts "discovered title for #{source.url}: #{title}"
      title
    end

    def discover_feed_url
      urls = Discovery.new(source.url).feed_urls
      url = urls.reject { |url| url =~ /comment/ }.first
      puts "discovered feed url for #{source.url}: #{url}" if url
      url || source.url
    end

    def update_entries
      parse.entries.each do |data|
        item = Item.new(source.url, source.team_id, data)
        raise "can not find guid for item in source #{source.feed_url}" unless item.guid
        # puts "processing item #{item.guid}: #{item.title}"
        record = Activity.where(:guid => item.guid).first
        attrs = item.attrs.merge(img_url: record.try(:img_url) || Image.new(item.url).store)
        record ? record.update_attributes!(attrs) : Activity.create!(attrs)
      end
    end

    def parse
      silence_warnings do
        puts "Feeds: going to fetch #{source.feed_url}"
        data = Feedzirra::Feed.fetch_and_parse(source.feed_url)
        puts "this does not look like a valid feed" unless data.respond_to?(:entries)
        data
      end
    end
end
