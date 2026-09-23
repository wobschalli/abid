require_relative 'components/master'

class Login < Phlex::HTML
  include Components

  def initialize(error: nil)
    @error = error
  end

  def view_template
    SkinnyLayout(title: 'Sign in — Abid') do
      div(class: 'flex flex-col gap-5 p-6 rounded-xl border border-line bg-surface') do
        header
        p(role: 'alert', class: 'text-[12.5px] text-danger') { @error } if @error
        form_body
        hint
      end
    end
  end

  private

  def header
    div(class: 'flex flex-col gap-1') do
      div(class: 'flex items-center gap-2') do
        img src: url('logo.webp'), alt: '', class: 'w-6 h-6 object-contain'
        span(class: 'font-display font-bold text-lg -tracking-[.015em]') { 'Abid' }
      end
      span(class: 'text-[12.5px] text-ink/65') { 'Rides for Abide CF' }
    end
  end

  def form_body
    form(method: 'post', action: path('/login'), class: 'flex flex-col gap-3.5') do
      field('Username') do
        input(type: 'text', name: 'username', autocomplete: 'username',
              autocapitalize: 'none', autofocus: true, required: true, class: 'board-input')
      end
      field('Login code') do
        input(type: 'password', name: 'password', autocomplete: 'current-password',
              required: true, class: 'board-input')
      end
      button(type: 'submit', class: 'board-btn-solid w-full') { 'Sign in' }
    end
  end

  def field(label, &block)
    div(class: 'flex flex-col gap-[5px]') do
      span(class: 'board-label') { label }
      yield
    end
  end

  def hint
    p(class: 'text-[12px] leading-[1.6] text-ink/60 pt-1 border-t border-line') do
      plain 'Leaders can get a login code by running '
      code(class: 'font-mono text-[11.5px] text-ink/80') { '/login' }
      plain ' in Discord — the bot DMs it to you.'
    end
  end
end
