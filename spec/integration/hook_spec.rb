require 'spec_helper'

describe Premailer::Rails::Hook do
  def run_hook(message)
    Premailer::Rails::Hook.perform(message)
  end

  def body_content(message)
    Nokogiri::HTML(message.html_string).at('body').content.gsub("\r\n", "\n")
  end

  class Mail::Message
    def html_string
      (html_part || self).body.to_s
    end
  end

  let(:message) { Fixtures::Message.with_parts(:html) }
  let(:processed_message) { run_hook(message) }

  describe '.delivering_email' do
    it 'is an alias to .perform' do
      method = described_class.method(:delivering_email)
      expected_method = described_class.method(:perform)

      expect(method).to eq expected_method
    end
  end

  describe '.previewing_email' do
    it 'is an alias to .perform' do
      method = described_class.method(:previewing_email)
      expected_method = described_class.method(:perform)

      expect(method).to eq expected_method
    end
  end

  it 'inlines the CSS' do
    expect { run_hook(message) }.to \
      change { message.html_string.include?("<p style=") }
  end

  it 'replaces the html part with an alternative part containing text and html parts' do
    expect(processed_message.content_type).to include('multipart/alternative')
    expected_parts = [message.html_part, message.text_part]
    expect(processed_message.parts).to match_array(expected_parts)
  end

  it 'does not screw up the text by maintaining the original body encoding' do
    raw_msg = Fixtures::Message.latin_message
    processed_msg = Fixtures::Message.latin_message
    run_hook(processed_msg)
    expect(body_content(processed_msg)).to eq(body_content(raw_msg))

    raw_msg = Fixtures::Message.non_latin_message
    processed_msg = Fixtures::Message.non_latin_message
    run_hook(processed_msg)
    expect(body_content(processed_msg)).to eq(body_content(raw_msg))

    raw_msg = Fixtures::Message.greek_message
    processed_msg = Fixtures::Message.greek_message
    run_hook(processed_msg)
    expect(body_content(processed_msg)).to eq(body_content(raw_msg))

    raw_msg = Fixtures::Message.dash_message
    processed_msg = Fixtures::Message.dash_message
    run_hook(processed_msg)
    expect(body_content(processed_msg)).to eq(body_content(raw_msg))
  end

  it 'supports US-ASCII output' do
    Premailer::Rails.config.merge!(output_encoding: 'US-ASCII')

    raw_msg = Fixtures::Message.latin_message
    processed_msg = Fixtures::Message.latin_message
    run_hook(processed_msg)
    expect(body_content(processed_msg)).to eq(body_content(raw_msg))

    raw_msg = Fixtures::Message.non_latin_message
    processed_msg = Fixtures::Message.non_latin_message
    run_hook(processed_msg)
    expect(body_content(processed_msg)).to eq(body_content(raw_msg))

    raw_msg = Fixtures::Message.greek_message
    processed_msg = Fixtures::Message.greek_message
    run_hook(processed_msg)
    expect(body_content(processed_msg)).to eq(body_content(raw_msg))

    raw_msg = Fixtures::Message.dash_message
    processed_msg = Fixtures::Message.dash_message
    run_hook(processed_msg)
    expect(body_content(processed_msg)).to eq(body_content(raw_msg))
  ensure
    Premailer::Rails.config.delete(:output_encoding)
  end

  it 'generates a text part from the html' do
    expect { run_hook(message) }.to change(message, :text_part)
  end

  context 'when message contains no html' do
    let(:message) { Fixtures::Message.with_parts(:text) }

    it 'does not modify the message' do
      expect { run_hook(message) }.to_not change(message, :html_string)
    end
  end

  context 'when message also contains a text part' do
    let(:message) { Fixtures::Message.with_parts(:html, :text) }

    it 'does not generate a text part' do
      expect { run_hook(message) }.to_not change(message, :text_part)
    end

    it 'does not replace any message part' do
      expect { run_hook(message) }.to_not \
        change { message.all_parts.map(&:content_type).sort }
    end
  end

  context 'when text generation is disabled' do
    it 'does not generate a text part' do
      begin
        Premailer::Rails.config[:generate_text_part] = false

        expect { run_hook(message) }.to_not change(message, :text_part)
      ensure
        Premailer::Rails.config[:generate_text_part] = true
      end
    end
  end

  context 'when message also contains an attachment' do
    let(:message) { Fixtures::Message.with_parts(:html, :attachment) }
    it 'does not mess with it' do
      expect(message.content_type).to include 'multipart/mixed'
      expect(message.parts.first.content_type).to include 'text/html'
      expect(message.parts.last.content_type).to include 'image/png'

      expect(processed_message.content_type).to include 'multipart/mixed'
      expect(processed_message.parts.first.content_type).to \
        include 'multipart/alternative'
      expect(processed_message.parts.last.content_type).to include 'image/png'
    end
  end

  context 'default skip premailer is true' do
    before do
      allow(Premailer::Rails).to receive(:config).and_return({default_skip_premailer: true})
    end

    it 'skips premailer if no message headers are set' do
      expect { run_hook(message) }.to_not change(message, :body)
    end

    it 'skips premailer if skip-premailer header is set' do
      message.header[:skip_premailer] = 'something'
      expect { run_hook(message) }.to_not change(message, :body)
    end

    it 'does not skip premailer if run-premailer header is set' do
      message.header[:run_premailer] = 'something'
      expect { run_hook(message) }.to change(message, :body)
    end

    it 'raises an exception if both skip and no-skip headers are set' do
      message.header[:skip_premailer] = 'something'
      message.header[:run_premailer] = 'something'
      expect { run_hook(message) }.to raise_error
    end
  end

  context 'default skip premailer is false' do
    before do
      allow(Premailer::Rails).to receive(:config).and_return({default_skip_premailer: false})
    end

    it 'does not skip premailer if no message headers are set' do
      expect { run_hook(message) }.to change(message, :body)
    end

    it 'skips premailer if skip-premailer header is set' do
      message.header[:skip_premailer] = 'something'
      expect { run_hook(message) }.to_not change(message, :body)
    end

    it 'does not skip premailer if run-premailer header is set' do
      message.header[:run_premailer] = 'something'
      expect { run_hook(message) }.to change(message, :body)
    end

    it 'raises an exception if both skip and no-skip headers are set' do
      message.header[:skip_premailer] = 'something'
      message.header[:run_premailer] = 'something'
      expect { run_hook(message) }.to raise_error
    end
  end

  it "should remove skip_premailer header" do
    message.header[:skip_premailer] = true
    expect { run_hook(message) }.to \
    change { message.header[:skip_premailer].nil? }.to(true)
  end

  it "should remove run_premailer header" do
    message.header[:run_premailer] = true
    expect { run_hook(message) }.to \
    change { message.header[:run_premailer].nil? }.to(true)
  end
end
