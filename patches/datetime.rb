class DateTime
  def parseable
    self.strftime '%Y-%m-%d %H:%M:%S'
  end
end
