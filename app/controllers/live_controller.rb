class LiveController < ApplicationController

  def ticker
    @resp = Class.new.extend(LiveHelper).ticker
    puts @resp

    respond_to do |format|
      format.html { redirect_to root_path}
      format.json { render json: @resp }
    end
  end

end
