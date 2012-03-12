require 'dataservice/util'

require 'rubygems'
require 'mechanize'
require 'log4r'
require 'csv'
require 'json'

module Google

  class MarketStatus # enum
    OPEN = :OPEN
    BEFORE_OPEN = :BEFORE_OPEN
    BEFORE_OPEN_DURING_GRACE_TIME = :BEFORE_OPEN_DURING_GRACE_TIME
    AFTER_CLOSE = :AFTER_CLOSE
    AFTER_CLOSE_DURING_GRACE_TIME = :AFTER_CLOSE_DURING_GRACE_TIME
  end

  class MarketTime
    # Constants
    MARKET_TIMES = {
      :open  => { :hour => 06, :min => 30 },
      :close => { :hour => 13, :min => 00 } }

    # Grace time before and after market hours where we do not want to
    # fetch data, allowing for data providers to settle
    GRACE_TIME_SECS_BEFORE_MARKET_OPEN = 60*60
    GRACE_TIME_SECS_AFTER_MARKET_CLOSE = 60*60

    # Accessors
    attr_accessor :updated_time
    attr_accessor :last_market_date
    attr_accessor :last_market_open_time
    attr_accessor :last_market_close_time
    attr_accessor :market_status

    def new()
      print(:asdfasdfjksdf)
      logger.debug("in new method")
      self.updateForce()
    end

    def updateForce()
      self.last_market_date = nil
      self.update()
    end

    def update()
      # We cache this value so we don't hit the servers every single time
      if (self.last_market_date == nil)
        # Hit the Google server to fetch the last market date
        self.last_market_date = GoogleTicker::FetchLastMarketDate()
        self.last_market_open_time = Util::ETime
          .new(self.last_market_date.year,
               self.last_market_date.mon,
               self.last_market_date.day,
               MARKET_TIMES[:open][:hour],
               MARKET_TIMES[:open][:min])
        self.last_market_close_time = Util::ETime
          .new(self.last_market_date.year,
               self.last_market_date.mon,
               self.last_market_date.day,
               MARKET_TIMES[:close][:hour],
               MARKET_TIMES[:close][:min])
      end
      
      now = Util::ETime.now()
      status = nil
      if false # Order of the following matters
        # Even the text alignnment
      elsif now.before?(self.last_market_open_time-GRACE_TIME_SECS_BEFORE_MARKET_OPEN)
        status = MarketStatus::BEFORE_OPEN_DURING_GRACE_TIME
      elsif now.before?(self.last_market_open_time)
        status = MarketStatus::BEFORE_OPEN
      elsif now.after?(self.last_market_close_time+GRACE_TIME_SECS_AFTER_MARKET_CLOSE)
        status = MarketStatus::AFTER_CLOSE_DURING_GRACE_TIME
      elsif now.after?(self.last_market_close_time)
        status = MarketStatus::AFTER_CLOSE
      else
        status = MarketStatus::OPEN
      end


      if now.before?(self.last_market_open_time.cloneDiffSeconds(-GRACE_TIME_SECS_BEFORE_MARKET_OPEN))
        status = MarketStatus::BEFORE_OPEN
      elsif
      

      
      self.updated_time = now
      self.market_status = status
    end
    
  end


  class GoogleTicker

    # http://www.google.com/finance?q=akam
    STOCK_URI  = URI('http://www.google.com/finance')
    
    # http://www.google.com/finance/historical?q=AKAM \
    #   &startdate=20120201&enddate=20120210&output=csv
    HISTORICAL_STOCK_DATA_URI = URI('http://www.google.com/finance/historical')
    
    # http://www.google.com/finance/option_chain?q=akam
    # 
    # http://www.google.com/finance/option_chain? \
    #   q=akam&expd=17&expm=3&expy=2012&output=json
    CURRENT_OPTION_DATA_URI = URI('http://www.google.com/finance/option_chain')
    
    @@agent = Mechanize.new()
    @@agent.user_agent_alias = 'Mac Safari'

    def initialize(ticker)
      @ticker = ticker
    end
    
    def doesTickerExist()
      # 7 days ago
      s = Util::ETime.now().cloneDiffSeconds(-7*60*60*24).to_strYYYYMMDD()
      # 1 day ago
      e = Util::ETime.now().cloneDiffSeconds(-1*60*60*24).to_strYYYYMMDD()
      
      return (self.getHistoricalStockData(s, e) != nil)
    end
    
    # Returns Data Inclusive of Dates
    def getHistoricalStockData(startdate, enddate)
      params = {
        :q         => @ticker,
        :startdate => startdate,
        :enddate   => enddate,
        :output    => :csv
      }

      page = nil
      begin
        page = @@agent.get(HISTORICAL_STOCK_DATA_URI, params)
      rescue => e
        return nil
      end

      # 10-Mar-11,36.12,36.75,35.52,36.41,4697535
      # 1-Apr-11,38.15,38.45,37.39,37.60,3492166
      # 2-May-11,34.41,34.75,34.06,34.23,6247551
      # 1-Jun-11,33.90,34.41,33.19,33.19,5231851
      # 1-Jul-11,31.49,31.49,31.49,31.49,0
      # 1-Aug-11,24.53,24.79,23.53,23.76,6650898
      # 1-Sep-11,22.03,22.28,21.41,21.46,2999834
      # 3-Oct-11,19.73,19.93,18.59,18.65,5102852
      # 1-Nov-11,25.91,27.00,25.73,26.64,5835498
      # 1-Dec-11,28.82,29.50,28.62,29.16,3638788
      # 3-Jan-12,32.97,33.20,32.77,32.93,4668332
      # 1-Feb-12,32.19,32.50,31.45,32.01,4530573
      # 1-Mar-12,36.20,36.26,35.87,35.90,4596809

      ret = []
      first = true
      CSV.parse(page.body) do |r|
        # Skip header row
        #   Date,Open,High,Low,Close,Volume
        if first == true
          first = false
          next
        end
        
        ret.push({ :date   => Date.parse(r[0]).strftime("%Y-%m-%d"),
                   :open   => Integer(r[1].to_f() * 100),
                   :high   => Integer(r[2].to_f() * 100),
                   :low    => Integer(r[3].to_f() * 100),
                   :close  => Integer(r[4].to_f() * 100),
                   :volume => Integer(r[5]) })
      end

      return ret
    end
    
    # Returns list of all current active option dates
    def getOptionDates()
      params = {
        :q      => @ticker,
      }

      page = nil
      begin
        page = @@agent.get(CURRENT_OPTION_DATA_URI, params)
      rescue => e
        logger.error("Unable to find option dates for #{@ticker}")
        return nil
      end

      exp = page.body.scan(/^google.finance.data =.*expirations:(\[.*?\]).*$/)
        .pop().pop()
        .gsub(/(\w+):/, '"\1":') # convert to proper json
      
      ret = []
      for j in JSON.parse(exp)
        ret.push(Date.new(j['y'], j['m'], j['d']).strftime("%Y-%m-%d"))
      end
      return ret
    end
    
    # Returns option data for a particular date
    def getOptionData(dateStr)
      dateParts = dateStr.split('-')
      params = {
        :q      => @ticker,
        :expd   => dateParts[2],
        :expm   => dateParts[1],
        :expy   => dateParts[0],
        :output => :json
      }
      page = nil
      begin
        page = @@agent.get(CURRENT_OPTION_DATA_URI, params)
      rescue => e
        logger.error("Unable to find option data for #{@ticker}")
        return nil
      end
      
      ret = JSON.parse(page.body.gsub(/(\w+):/, '"\1":')) # convert to proper json
      return ret
    end

    def GoogleTicker.FetchLastMarketDate()
      ticker = '.DJI'
      params = {
        :q      => ticker,
      }
      
      # Fetch the page
      page = nil
      begin
        page = @@agent.get(STOCK_URI, params)
      rescue => e
        logger.error("Unable to find times for #{@ticker}")
        return nil
      end
      
      # The following date status is always show to be the current or
      # last market open date.  It looks like: "Mar 9 - Close" on
      # March 11th which is a Sunday.
      dateStatus = page.body.scan(/<span class=nwp>\s*?(\w+) (\d+) - (\w+)\s*?<\/span>/).pop()
      mon = dateStatus[0]
      day = dateStatus[1]
      # Unused: dateStatus[3] which might be 'Open' or 'Close'
      
      # The date string that we parse does not come with a year.
      # Figure out the right year while accounting for yearly
      # boundaries. Take care of case where last market date was:
      # 12/31/2011 but current date is 01/01/2012
      now = Util::ETime.new()
      marketDate = Util::ETime.FromDate(Date.parse("#{day}-#{mon}-#{now.year}"))
      if (now.dateBefore?(marketDate))
        marketDate = Util::ETime.FromDate(Date.parse("#{day}-#{mon}-#{now.year-1}"))
      end

      return marketDate
    end
    
    def logger()
      return Rails.logger
    end
    
  end
  
end

COMMENT = <<END
calls:
puts:
- cid: '681345055999672'
  name: ''
  s: AKAM120317P00020000
  e: OPRA
  p: ! '-'
  c: ! '-'
  b: ! '-'
  a: '0.01'
  oi: '      0'
  vol: ! '-'
  strike: '20.00'
  expiry: Mar 17, 2012
- cid: '311136124377695'
  name: ''
  s: AKAM120317P00034000
  e: OPRA
  p: '0.48'
  cs: chg
  c: '+0.20'
  cp: '71.43'
  b: '0.47'
  a: '0.49'
  oi: '   1430'
  vol: '    226'
  strike: '34.00'
  expiry: Mar 17, 2012
END

