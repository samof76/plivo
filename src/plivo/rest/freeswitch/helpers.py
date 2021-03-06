# -*- coding: utf-8 -*-
# Copyright (c) 2011 Plivo Team. See LICENSE for details.

from gevent import monkey
monkey.patch_all()

import base64
import ConfigParser
from hashlib import sha1
import hmac
import httplib
import os.path
import re
import urllib
import urllib2
import urlparse

from werkzeug.datastructures import MultiDict


def get_substring(start_char, end_char, data):
    if data is None or not data:
        return ""
    start_pos = data.find(start_char)
    if start_pos < 0:
        return ""
    end_pos = data.find(end_char)
    if end_pos < 0:
        return ""
    return data[start_pos+len(start_char):end_pos]


def url_exists(url):
    p = urlparse.urlparse(url)
    try:
        connection = httplib.HTTPConnection(p[1])
        connection.request('HEAD', p[2])
        response = connection.getresponse()
        connection.close()
        return response.status == httplib.OK
    except Exception:
        return False


def file_exists(filepath):
    return os.path.isfile(filepath)


def get_config(filename):
    config = ConfigParser.SafeConfigParser()
    config.read(filename)
    return config


def get_post_param(request, key):
    try:
        return request.form[key]
    except MultiDict.KeyError:
        return ""


def get_conf_value(config, section, key):
    try:
        value = config.get(section, key)
        return str(value)
    except (ConfigParser.NoSectionError, ConfigParser.NoOptionError):
        return ""


def is_valid_url(value):
    regex = re.compile(
      r'^(?:http|ftp)s?://'  # http:// or https://
      r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+(?:[A-Z]{2,6}\.?|[A-Z0-9-]{2,}\.?)|'  # domain
      r'localhost|'  # localhost
      r'http://127.0.0.1|'  # 127.0.0.1
      r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'  # or ip
      r'(?::\d+)?'  # optional port
      r'(?:/?|[/?]\S+)$', re.IGNORECASE)

    # If no domain starters we assume its http and add it
    if not value.startswith('http://') and not value.startswith('https://') \
        and not value.startswith('ftp://'):
        value = ''.join(['http://', value])

    if regex.search(value):
        return True
    # Trivial case failed. Try for possible IDN domain
    if value:
        scheme, netloc, path, query, fragment = urlparse.urlsplit(value)
        try:
            netloc = netloc.encode('idna')  # IDN -> ACE
        except UnicodeError:  # invalid domain part
            return False
        url = urlparse.urlunsplit((scheme, netloc, path, query, fragment))
        if regex.search(url):
            return True

    return False


class HTTPErrorProcessor(urllib2.HTTPErrorProcessor):
    def https_response(self, request, response):
        code, msg, hdrs = response.code, response.msg, response.info()
        if code >= 300:
            response = self.parent.error(
                'http', request, response, code, msg, hdrs)
        return response


class HTTPUrlRequest(urllib2.Request):
    def get_method(self):
        if getattr(self, 'http_method', None):
            return self.http_method
        return urllib2.Request.get_method(self)


class HTTPRequest:
    """Helper class for preparing HTTP requests.
    """
    USER_AGENT = 'Plivo'

    def __init__(self, auth_id='', auth_token=''):
        """initialize a object

        auth_id: Plivo SID/ID
        auth_token: Plivo token

        returns a HTTPRequest object
        """
        self.auth_id = auth_id
        self.auth_token = auth_token
        self.opener = None

    def _build_get_uri(self, uri, params):
        if params:
            if uri.find('?') > 0:
                if uri[-1] != '&':
                    uri += '&'
                uri = uri + urllib.urlencode(params)
            else:
                uri = uri + '?' + urllib.urlencode(params)
        return uri

    def _prepare_http_request(self, uri, params, method='POST'):
        # install error processor to handle HTTP 201 response correctly
        if self.opener == None:
            self.opener = urllib2.build_opener(HTTPErrorProcessor)
            urllib2.install_opener(self.opener)

        if method and method == 'GET':
            uri = self._build_get_uri(uri, params)
            request = HTTPUrlRequest(uri)
        else:
            request = HTTPUrlRequest(uri, urllib.urlencode(params))
            if method and (method == 'DELETE' or method == 'PUT'):
                request.http_method = method

        request.add_header('User-Agent', self.USER_AGENT)

        # append the POST variables sorted by key to the uri
        s = uri
        for k, v in sorted(params.items()):
            s += k + v

        # compute signature and compare signatures
        signature =  base64.encodestring(hmac.new(self.auth_token, s, sha1).\
                                                            digest()).strip()
        request.add_header("X_PLIVO_SIGNATURE", "%s" % signature)

        # be sure 100 continue is disabled
        request.add_header("Expect", "")
        return request

    def fetch_response(self, uri, params={}, method='POST'):
        if not method in ('GET', 'POST'):
            raise NotImplementedError('HTTP %s method not implemented' \
                                                            % method)
        # Read all params in the query string and include them in params
        query = urlparse.urlsplit(uri)[3]
        args = query.split('&')
        for arg in args:
            try:
                k, v = arg.split('=')
                params[k] = v
            except ValueError:
                pass

        request = self._prepare_http_request(uri, params, method)
        response = urllib2.urlopen(request).read()
        return response
