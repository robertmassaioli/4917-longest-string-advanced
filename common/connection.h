#ifndef __LONGEST_STRING_CONNECTION
#define __LONGEST_STRING_CONNECTION

#include <vector>
#include <boost/ref.hpp>
#include <boost/bind.hpp>
#include <boost/asio.hpp>
#include <boost/tuple/tuple.hpp>
#include <boost/archive/text_oarchive.hpp>
#include <boost/archive/text_iarchive.hpp>

class connection
{
   public:
      connection(boost::asio::io_service& io_service) 
         : socket_(io_service)
      {
      }

      boost::asio::ip::tcp::socket& socket()
      {
         return socket_;
      }

      template<typename T, typename Handler>
      void async_write(const T& data, Handler handler) 
      {
         // serialize the data
         std::ostringstream data_stream;
         boost::archive::text_oarchive archive(data_stream);
         archive << data;

         // build the header of the message
         std::ostringstream header_stream;
         header_stream 
            << std::setw(header_length) 
            << std::hex
            << data_stream.str().size();
         if(!header_stream || header_stream.str().size() != header_length) 
         {
            // something went wrong so display an error message.
            boost::system::error_code error(boost::asio::error::invalid_argument);
            socket_.get_io_service().post(boost::bind(handler, error));
            return;
         }

         // write out the header and data
         std::vector<boost::asio::const_buffer> buffers;
         buffers.push_back(boost::asio::buffer(header_stream.str()));
         buffers.push_back(boost::asio::buffer(data_stream.str()));
         boost::asio::async_write(socket_, buffers, handler);

      }

      template<typename T, typename Handler>
      void async_read(T& data, Handler handler) 
      {
         
         void (connection::*f)(
               const boost::system::error_code&,
               const std::size_t&,
               T&,
               boost::tuple<Handler>) =
            &connection::handle_read_header<T, Handler>;


         // read the header out
         boost::asio::async_read(
               socket_, 
               boost::asio::buffer(inbound_header_),
               boost::bind(
                  f,
                  this,
                  boost::asio::placeholders::error,
                  boost::asio::placeholders::bytes_transferred,
                  boost::ref(data),
                  boost::make_tuple(handler)
               ));
               

         // read out the number of bytes that make up the data
         // read the data into the object
      }

   private:
      template<typename T, typename Handler>
      void handle_read_header(
            const boost::system::error_code& error,
            const std::size_t& bytes_transferred,
            T& data,
            boost::tuple<Handler> handler
            ) 
      {
         // the header contains the data. Read the length and read that much into the
         // data vector.
         if(error) 
         {
            boost::get<0>(handler)(error);
         } 
         else 
         {
            std::istringstream header_in(std::string(inbound_header_, header_length));
            std::size_t inbound_data_size = 0;
            if(!(header_in >> std::hex >> inbound_data_size)) 
            {
               // Header doesn't seem to be valid. Inform the caller.
               boost::system::error_code error(boost::asio::error::invalid_argument);
               boost::get<0>(handler)(error);
               return;
            }

            inbound_data_.resize(inbound_data_size);

            void (connection::*f)(
                  const boost::system::error_code&,
                  const std::size_t& bytes_transferred,
                  T&,
                  boost::tuple<Handler>)
               = &connection::handle_read_data<T, Handler>;
            
            boost::asio::async_read(
                  socket_,
                  boost::asio::buffer(inbound_data_),
                  boost::bind(
                     f,
                     this,
                     boost::asio::placeholders::error,
                     boost::asio::placeholders::bytes_transferred,
                     boost::ref(data),
                     handler)
                  );
         }
      }

      template<typename T, typename Handler>
      void handle_read_data(
            const boost::system::error_code& error,
            const std::size_t& bytes_transferred,
            T& data,
            boost::tuple<Handler> handler
            )
      {
         if(error) 
         {
            boost::get<0>(handler)(error);
         } 
         else 
         {
            try 
            {
               std::string archive_data(&inbound_data_[0], inbound_data_.size());
               std::istringstream archive_stream(archive_data);
               boost::archive::text_iarchive in_archive(archive_stream);
               in_archive >> data;
            }
            catch (std::exception& exception) 
            {
               // Unable to decode data.
               boost::system::error_code error(boost::asio::error::invalid_argument);
               boost::get<0>(handler)(error);
               return;
            }

            boost::get<0>(handler)(error);
         }
      }

      enum { header_length = 8 };

      boost::asio::ip::tcp::socket socket_;

      char inbound_header_[header_length];
      std::vector<char> inbound_data_;
};

#endif
