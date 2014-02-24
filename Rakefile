task :install do
	system("bundle install --path=vendor/bundle --binstubs=bin")
	system("sudo bash test/travis_install.sh")
end
task :test do
	Dir.glob("test/*.rb") do |f|
		p "run %s" % [f]
		raise ("%s error" % [f]) unless system("bundle exec ruby src/main.rb %s" % [f])
	end
end
